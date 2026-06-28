-- ============================================================================
-- Correções em massa (Frente A) — uma RPC, relatório por linha
-- ----------------------------------------------------------------------------
-- Recebe um array de ações vindo do xlsx importado. Cada linha é uma ação
-- EXPLÍCITA (sem reconciliação mágica que apague registos reais):
--   adicionar  : codigo + data + hora + tipo   -> corrigir_picagem (append)
--   anular     : picagem_id                     -> anular_picagem (soft-void)
--   substituir : picagem_id + data + hora       -> anular + corrigir (mesma
--                                                  pessoa/tipo, nova hora)
-- Cada linha corre no seu próprio bloco: um erro numa linha não derruba o lote
-- (savepoint implícito do BEGIN/EXCEPTION). Devolve [{linha, acao, ok, erro?}].
-- Tudo continua append-only e auditado (correcao_manual + criada_por/anulada_por).
-- ============================================================================

begin;

create or replace function public.aplicar_correcoes(p_linhas jsonb)
returns jsonb language plpgsql security definer set search_path to '' as $function$
declare
  v_emp uuid := public.empresa_atual();
  v_out jsonb := '[]'::jsonb;
  v_row jsonb; v_i int := 0;
  v_acao text; v_codigo text; v_tipo text; v_motivo text; v_pid uuid;
  v_trab uuid; v_momento timestamptz; v_res json; v_tipo_exist text;
begin
  if not public.is_admin() then
    raise exception 'apenas administradores' using errcode='insufficient_privilege';
  end if;

  for v_row in select * from jsonb_array_elements(p_linhas) loop
    v_i := v_i + 1;
    begin
      v_acao := lower(trim(v_row->>'acao'));
      v_motivo := coalesce(nullif(trim(v_row->>'motivo'),''), 'correção em massa');

      if v_acao = 'adicionar' then
        v_codigo := trim(v_row->>'codigo');
        select id into v_trab from public.trabalhador where empresa_id=v_emp and codigo_pessoal=v_codigo;
        if v_trab is null then raise exception 'colaborador % não encontrado', v_codigo; end if;
        v_tipo := lower(trim(v_row->>'tipo'));
        v_momento := ((v_row->>'data')||' '||(v_row->>'hora'))::timestamp at time zone 'Europe/Lisbon';
        v_res := public.corrigir_picagem(v_trab, v_tipo, v_momento, v_motivo, null);
        v_out := v_out || jsonb_build_object('linha',v_i,'acao','adicionar','ok',true,'picagem_id',v_res->>'picagem_id');

      elsif v_acao = 'anular' then
        v_pid := (v_row->>'picagem_id')::uuid;
        perform public.anular_picagem(v_pid, v_motivo);
        v_out := v_out || jsonb_build_object('linha',v_i,'acao','anular','ok',true);

      elsif v_acao = 'substituir' then
        v_pid := (v_row->>'picagem_id')::uuid;
        select v.trabalhador_id, p.tipo into v_trab, v_tipo_exist
          from public.picagem p
          join public.verificacao v on v.id=p.verificacao_id and v.empresa_id=p.empresa_id
         where p.id=v_pid and p.empresa_id=v_emp and not p.anulada;
        if v_trab is null then raise exception 'picagem não encontrada ou já anulada'; end if;
        v_momento := ((v_row->>'data')||' '||(v_row->>'hora'))::timestamp at time zone 'Europe/Lisbon';
        perform public.anular_picagem(v_pid, v_motivo);
        v_res := public.corrigir_picagem(v_trab, v_tipo_exist, v_momento, v_motivo, null);
        v_out := v_out || jsonb_build_object('linha',v_i,'acao','substituir','ok',true,'picagem_id',v_res->>'picagem_id');

      elsif v_acao is null or v_acao = '' then
        v_out := v_out || jsonb_build_object('linha',v_i,'ok',true,'ignorada',true);
      else
        raise exception 'ação desconhecida: %', v_acao;
      end if;

    exception when others then
      v_out := v_out || jsonb_build_object('linha',v_i,'ok',false,'erro',sqlerrm);
    end;
  end loop;

  return v_out;
end
$function$;

revoke all on function public.aplicar_correcoes(jsonb) from public;
grant execute on function public.aplicar_correcoes(jsonb) to authenticated;

commit;
