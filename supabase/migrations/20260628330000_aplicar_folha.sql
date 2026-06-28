-- ============================================================================
-- Folha de horas (Frente A) — reconciliação intuitiva, com pré-visualização
-- ----------------------------------------------------------------------------
-- O gestor pensa numa FOLHA: uma linha por colaborador por dia, com as horas.
-- Recebe [{codigo, data, entrada, inicio_pausa, fim_pausa, saida}] e, para cada
-- célula PREENCHIDA, reconcilia contra o que existe nesse dia:
--   não existe        -> ADICIONA
--   existe e difere   -> SUBSTITUI (anula a antiga + cria a nova)
--   existe e igual     -> nada
--   célula em branco  -> NÃO MEXE (nunca apaga sozinho)
--
-- Dias "complexos" (mais de uma picagem do mesmo tipo, ex. dois turnos) são
-- IGNORADOS e reportados — editam-se na ficha do colaborador.
--
-- p_simular = true  -> só calcula e devolve o plano (pré-visualização).
-- p_simular = false -> aplica. Tudo via corrigir_picagem/anular_picagem
-- (append-only, auditado: correcao_manual + autor).
-- ============================================================================

begin;

create or replace function public.aplicar_folha(p_linhas jsonb, p_simular boolean default true)
returns jsonb language plpgsql security definer set search_path to '' as $function$
declare
  v_emp uuid := public.empresa_atual();
  v_row jsonb; v_i int := 0;
  v_codigo text; v_data date; v_trab uuid; v_complexo boolean;
  v_add int := 0; v_sub int := 0; v_nada int := 0;
  v_complexos jsonb := '[]'; v_erros jsonb := '[]'; v_det jsonb := '[]';
  v_slot record; v_desejado text; v_momento timestamptz;
  v_eid uuid; v_ehora text;
begin
  if not public.is_admin() then
    raise exception 'apenas administradores' using errcode='insufficient_privilege';
  end if;

  for v_row in select * from jsonb_array_elements(p_linhas) loop
    v_i := v_i + 1;
    begin
      v_codigo := trim(coalesce(v_row->>'codigo',''));
      if v_codigo = '' then continue; end if;
      v_data := (v_row->>'data')::date;

      select id into v_trab from public.trabalhador where empresa_id=v_emp and codigo_pessoal=v_codigo;
      if v_trab is null then raise exception 'colaborador % não encontrado', v_codigo; end if;

      -- dia complexo? (mais de uma picagem do mesmo tipo)
      select bool_or(c>1) into v_complexo from (
        select p.tipo, count(*) c
        from public.picagem p
        join public.verificacao v on v.id=p.verificacao_id and v.empresa_id=p.empresa_id
        where v.empresa_id=v_emp and v.trabalhador_id=v_trab and not p.anulada
          and date_trunc('day', v.momento_dispositivo at time zone 'Europe/Lisbon')::date = v_data
        group by p.tipo) z;
      if coalesce(v_complexo,false) then
        v_complexos := v_complexos || jsonb_build_object('codigo',v_codigo,'data',v_data::text);
        continue;
      end if;

      for v_slot in select * from (values
        ('entrada','entrada'), ('inicio_pausa','inicio_intervalo'),
        ('fim_pausa','fim_intervalo'), ('saida','saida')) as s(col,tipo)
      loop
        v_desejado := nullif(trim(coalesce(v_row->>v_slot.col,'')),'');
        if v_desejado is null then continue; end if;  -- branco = sem alteração
        v_momento := (v_data::text || ' ' || v_desejado)::timestamp at time zone 'Europe/Lisbon';

        select p.id, to_char(v.momento_dispositivo at time zone 'Europe/Lisbon','HH24:MI')
          into v_eid, v_ehora
          from public.picagem p
          join public.verificacao v on v.id=p.verificacao_id and v.empresa_id=p.empresa_id
         where v.empresa_id=v_emp and v.trabalhador_id=v_trab and not p.anulada and p.tipo=v_slot.tipo
           and date_trunc('day', v.momento_dispositivo at time zone 'Europe/Lisbon')::date = v_data
         limit 1;

        if v_eid is null then
          v_add := v_add + 1;
          v_det := v_det || jsonb_build_object('codigo',v_codigo,'data',v_data::text,
            'tipo',v_slot.tipo,'accao','adicionar','para',v_desejado);
          if not p_simular then
            perform public.corrigir_picagem(v_trab, v_slot.tipo, v_momento, 'folha de horas', null);
          end if;
        elsif v_ehora <> v_desejado then
          v_sub := v_sub + 1;
          v_det := v_det || jsonb_build_object('codigo',v_codigo,'data',v_data::text,
            'tipo',v_slot.tipo,'accao','substituir','de',v_ehora,'para',v_desejado);
          if not p_simular then
            perform public.anular_picagem(v_eid, 'folha de horas');
            perform public.corrigir_picagem(v_trab, v_slot.tipo, v_momento, 'folha de horas', null);
          end if;
        else
          v_nada := v_nada + 1;
        end if;

        v_eid := null; v_ehora := null;
      end loop;

    exception when others then
      v_erros := v_erros || jsonb_build_object('linha',v_i,'codigo',v_codigo,
        'data',v_row->>'data','erro',sqlerrm);
    end;
  end loop;

  return jsonb_build_object(
    'simulado', p_simular,
    'adicionar', v_add, 'substituir', v_sub, 'sem_alteracao', v_nada,
    'complexos', v_complexos, 'erros', v_erros, 'detalhes', v_det);
end
$function$;

revoke all on function public.aplicar_folha(jsonb, boolean) from public;
grant execute on function public.aplicar_folha(jsonb, boolean) to authenticated;

commit;
