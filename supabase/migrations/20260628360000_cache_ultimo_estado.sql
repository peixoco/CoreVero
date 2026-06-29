-- ============================================================================
-- Cache de PIN passa a trazer o ÚLTIMO estado de cada trabalhador (Frente A — UX)
-- ----------------------------------------------------------------------------
-- Para o kiosk mostrar só as opções de tipo VÁLIDAS também offline (online já o
-- faz via iniciar_picagem). A cache passa a incluir, por trabalhador, o tipo e
-- o momento da última picagem (não-anulada). Offline, o kiosk combina isto com
-- as picagens locais ainda por enviar para saber o estado real de hoje.
--
-- A assinatura de RETURNS TABLE muda -> é preciso DROP + CREATE.
-- ============================================================================

begin;

drop function if exists public.obter_cache_pins();

create function public.obter_cache_pins()
returns table(
  codigo_pessoal text, nome text, trabalhador_id uuid, pin_hmac text,
  ultimo_tipo text, ultimo_momento timestamptz)
language plpgsql security definer set search_path to ''
as $function$
declare
  v_empresa uuid := public.empresa_atual();
  v_loja    uuid := public.loja_atual();
  v_chave   text;
begin
  if not public.is_kiosk() then
    raise exception 'apenas o kiosk pode obter a cache' using errcode = 'insufficient_privilege';
  end if;
  if not public.kiosk_ativo() then
    raise exception 'kiosk revogado — contacte o gestor' using errcode = 'insufficient_privilege';
  end if;
  if v_empresa is null or v_loja is null then
    raise exception 'identidade de kiosk inválida' using errcode = 'insufficient_privilege';
  end if;

  select k.chave_hmac into v_chave from public.kiosk k where k.id = auth.uid();
  if v_chave is null then
    raise exception 'chave do dispositivo não registada';
  end if;

  return query
    select t.codigo_pessoal, t.nome, t.id,
           encode(extensions.hmac(t.codigo_pessoal || ':' || t.pin, v_chave, 'sha256'), 'hex') as pin_hmac,
           u.tipo, u.momento_dispositivo
      from public.trabalhador t
      left join lateral (
        select p.tipo, v.momento_dispositivo
          from public.picagem p
          join public.verificacao v on v.id=p.verificacao_id and v.empresa_id=p.empresa_id
         where v.empresa_id = v_empresa and v.trabalhador_id = t.id and not p.anulada
         order by v.momento_dispositivo desc limit 1
      ) u on true
     where t.empresa_id = v_empresa and t.ativo = true and t.pin is not null;
end
$function$;

revoke all on function public.obter_cache_pins() from public;
grant execute on function public.obter_cache_pins() to authenticated;

commit;