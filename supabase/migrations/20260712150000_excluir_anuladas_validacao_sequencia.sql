-- P1 (doc 09 v2): sequencia_valida e iniciar_picagem não excluíam picagens anuladas.
-- A coluna picagem.anulada (not null) nasceu numa migração posterior às funções e estas
-- nunca foram atualizadas; obter_cache_pins e corrigir_picagem_bloco já excluem.
-- Sintoma verificado: após uma anulação, o caminho offline oferece a opção correta
-- (e é recusada no drain) enquanto o online oferece a errada (e é aceite).
-- Alteração: "and not p.anulada" no lookup da picagem anterior, nas duas funções.
-- Nenhuma assinatura muda; tipos gerados não são afetados.

create or replace function public.sequencia_valida(p_empresa uuid, p_trabalhador uuid, p_tipo text, p_momento timestamp with time zone)
 returns boolean
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare v_ultimo text;
begin
  select p.tipo into v_ultimo
    from public.picagem p
    join public.verificacao v
      on v.id = p.verificacao_id and v.empresa_id = p.empresa_id
   where p.empresa_id = p_empresa
     and not p.anulada
     and v.trabalhador_id = p_trabalhador
     and v.momento_dispositivo < p_momento
     and date_trunc('day', (v.momento_dispositivo at time zone 'Europe/Lisbon'))
       = date_trunc('day', (p_momento            at time zone 'Europe/Lisbon'))
   order by v.momento_dispositivo desc
   limit 1;

  return case
    when v_ultimo is null              then p_tipo = 'entrada'
    when v_ultimo in ('entrada','fim_intervalo') then p_tipo in ('saida','inicio_intervalo')
    when v_ultimo = 'inicio_intervalo' then p_tipo = 'fim_intervalo'
    when v_ultimo = 'saida'            then p_tipo = 'entrada'
    else false
  end;
end
$function$;

create or replace function public.iniciar_picagem(p_codigo_pessoal text, p_pin text)
 returns json
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare
  v_empresa uuid := public.empresa_atual();
  v_loja    uuid := public.loja_atual();
  v_trab    record;
  v_ultima  record;
  v_aut     uuid := gen_random_uuid();
begin
  if not public.is_kiosk() then
    raise exception 'apenas o kiosk pode iniciar picagens'
      using errcode = 'insufficient_privilege';
  end if;
  if not public.kiosk_ativo() then
    raise exception 'kiosk revogado — contacte o gestor'
      using errcode = 'insufficient_privilege';
  end if;
  if v_empresa is null or v_loja is null then
    raise exception 'identidade de kiosk inválida (empresa/loja em falta no token)'
      using errcode = 'insufficient_privilege';
  end if;

  select t.id, t.nome
    into v_trab
    from public.trabalhador t
   where t.empresa_id     = v_empresa
     and t.codigo_pessoal = p_codigo_pessoal
     and t.ativo          = true
     and t.pin is not null
     and t.pin            = p_pin;

  if v_trab.id is null then
    raise exception 'código ou PIN inválido'
      using errcode = 'invalid_authorization_specification';
  end if;

  insert into public.autorizacao (id, empresa_id, trabalhador_id, loja_id, expira_em)
  values (v_aut, v_empresa, v_trab.id, v_loja, now() + interval '6 hours');

  select p.tipo, v.momento_dispositivo
    into v_ultima
    from public.picagem p
    join public.verificacao v
      on v.id = p.verificacao_id and v.empresa_id = p.empresa_id
   where p.empresa_id     = v_empresa
     and not p.anulada
     and v.trabalhador_id = v_trab.id
     and v.momento_dispositivo >=
         (date_trunc('day', (now() at time zone 'Europe/Lisbon')) at time zone 'Europe/Lisbon')
   order by v.momento_dispositivo desc
   limit 1;

  return json_build_object(
    'autorizacao_id', v_aut,
    'trabalhador_id', v_trab.id,
    'nome',           v_trab.nome,
    'ultima_tipo',    v_ultima.tipo,
    'ultima_momento', v_ultima.momento_dispositivo
  );
end
$function$;
