-- ============================================================================
-- Idempotência da picagem (Sprint 3a — fundação da outbox)
-- ----------------------------------------------------------------------------
-- Problema: quando a fila offline drena, se registar_picagem inserir mas a
-- resposta não voltar ao cliente (rede cai / app morre), a fila repete o item
-- e a picagem é inserida DUAS vezes. Num registo legal de tempos (CT art. 202),
-- duplicar é tão grave como perder.
--
-- Solução: cada item da fila nasce com uma CHAVE (uuid) gerada no cliente, que
-- viaja em todas as tentativas do mesmo toque. O servidor guarda-a; uma segunda
-- chamada com a mesma chave devolve o resultado anterior em vez de inserir.
--
-- Nota: a chave NÃO é o verificacao_id (esse continua a nascer no servidor). É
-- só o "número de série do toque". A autoridade do servidor mantém-se.
--
-- Robustez: como a função é transacional, uma chave só fica COMETIDA se a
-- verificacao E a picagem foram ambas inseridas. Logo:
--   - retomada sequencial (item já cometido, repetido) -> pré-check devolve-o;
--   - corrida (dois toques simultâneos com a mesma chave) -> o índice único
--     dispara unique_violation e devolvemos o existente.
-- ============================================================================

begin;

-- ----------------------------------------------------------------------------
-- 1. Coluna + índice único parcial (por empresa).
--    Nullable para não exigir backfill; o RPC novo preenche-a sempre.
-- ----------------------------------------------------------------------------
alter table public.verificacao
  add column if not exists chave_idempotencia uuid;

create unique index if not exists verificacao_empresa_chave_idem_key
  on public.verificacao (empresa_id, chave_idempotencia)
  where chave_idempotencia is not null;

-- ----------------------------------------------------------------------------
-- 2. registar_picagem — assinatura nova: + p_chave_idempotencia uuid.
--    Mantém o caminho por trabalhador da migração anterior.
-- ----------------------------------------------------------------------------
drop function if exists public.registar_picagem(text, text, text, timestamptz);

create or replace function public.registar_picagem(
  p_codigo_pessoal      text,
  p_pin                 text,
  p_tipo                text,
  p_momento_dispositivo timestamptz,
  p_chave_idempotencia  uuid
)
returns json
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_empresa uuid := public.empresa_atual();
  v_loja    uuid := public.loja_atual();
  v_trab    uuid;
  v_id      uuid := gen_random_uuid();
  v_path    text;
  v_exist_id   uuid;
  v_exist_path text;
begin
  if not public.is_kiosk() then
    raise exception 'apenas o kiosk pode registar picagens'
      using errcode = 'insufficient_privilege';
  end if;
  if v_empresa is null or v_loja is null then
    raise exception 'identidade de kiosk inválida (empresa/loja em falta no token)'
      using errcode = 'insufficient_privilege';
  end if;
  if p_tipo not in ('entrada','saida','inicio_intervalo','fim_intervalo') then
    raise exception 'tipo de picagem inválido: %', p_tipo;
  end if;
  if p_momento_dispositivo is null then
    raise exception 'momento do dispositivo em falta';
  end if;
  if p_chave_idempotencia is null then
    raise exception 'chave de idempotência em falta';
  end if;

  -- idempotência (retomada sequencial): a chave já foi processada?
  select id, foto_url into v_exist_id, v_exist_path
    from public.verificacao
   where empresa_id = v_empresa
     and chave_idempotencia = p_chave_idempotencia;

  if v_exist_id is not null then
    return json_build_object(
      'verificacao_id', v_exist_id,
      'foto_path',      v_exist_path,
      'repetida',       true
    );
  end if;

  -- validar credenciais
  select id into v_trab
    from public.trabalhador
   where empresa_id     = v_empresa
     and codigo_pessoal = p_codigo_pessoal
     and ativo          = true
     and pin is not null
     and pin            = p_pin;

  if v_trab is null then
    raise exception 'código ou PIN inválido'
      using errcode = 'invalid_authorization_specification';
  end if;

  -- caminho: {empresa}/{loja}/{trabalhador}/{verificacao_id}.jpg
  v_path := v_empresa::text || '/' || v_loja::text || '/'
            || v_trab::text || '/' || v_id::text || '.jpg';

  begin
    insert into public.verificacao
      (id, empresa_id, trabalhador_id, loja_id,
       momento_dispositivo, momento_servidor, foto_url, chave_idempotencia)
    values
      (v_id, v_empresa, v_trab, v_loja,
       p_momento_dispositivo, now(), v_path, p_chave_idempotencia);

    insert into public.picagem (empresa_id, verificacao_id, tipo)
    values (v_empresa, v_id, p_tipo);

  exception when unique_violation then
    -- corrida: outra chamada com a mesma chave ganhou. Devolve o existente.
    select id, foto_url into v_exist_id, v_exist_path
      from public.verificacao
     where empresa_id = v_empresa
       and chave_idempotencia = p_chave_idempotencia;
    return json_build_object(
      'verificacao_id', v_exist_id,
      'foto_path',      v_exist_path,
      'repetida',       true
    );
  end;

  return json_build_object(
    'verificacao_id', v_id,
    'foto_path',      v_path,
    'repetida',       false
  );
end
$function$;

revoke all on function public.registar_picagem(text, text, text, timestamptz, uuid) from public;
grant execute on function public.registar_picagem(text, text, text, timestamptz, uuid) to authenticated;

commit;
