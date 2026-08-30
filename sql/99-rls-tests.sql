-- =====================================================================
-- Chasing Excellence Scorecards — RLS regression suite
--
-- Safe to run against the live database: everything happens inside one
-- transaction that ends in ROLLBACK. It writes nothing.
--
-- Run it after ANY change to policies or helper functions. Every row must
-- say PASS.
--
-- Set the two uuids below to real auth.users ids. A owns the data, B is
-- the other person.
-- =====================================================================
begin;

create temp table res(step text, expected text, got text) on commit drop;
grant insert, select on res to authenticated;

do $t$
declare
  a uuid := '20eaf3b1-cc69-49e1-8fbc-eb059b1639b5';   -- owner
  b uuid := 'fefe7d14-9d05-425d-b35c-69660f99f44b';   -- other person
  tpl uuid; cat uuid; lib uuid; lib2 uuid; card uuid; itm uuid; n int; msg text; tmp uuid;
begin
  select id into tpl from public.sc_templates where slug='life-balance';
  select c.id into cat from public.sc_categories c where c.template_id=tpl and c.code='faith';
  select i.id into lib  from public.sc_library_items i where i.category_id=cat and i.code='pray';
  select i.id into lib2 from public.sc_library_items i where i.category_id=cat and i.code='attend-church';

  insert into public.sc_user_scorecards(owner, template_id) values (a, tpl) returning id into card;
  insert into public.sc_user_scorecard_items(user_scorecard_id, library_item_id, category_id, frequency)
    values (card, lib, cat, 'daily') returning id into itm;
  insert into public.sc_entries(user_scorecard_id, user_scorecard_item_id, period_start, value_bool)
    values (card, itm, date_trunc('month', current_date)::date, true);

  -- =================================================================
  -- A (owner)
  -- =================================================================
  set local role authenticated;
  perform set_config('request.jwt.claims', json_build_object('sub',a,'role','authenticated')::text, true);

  select count(*) into n from public.sc_user_scorecards where id = card;
  insert into res values ('owner sees own card','1',n::text);
  select count(*) into n from public.sc_entries where user_scorecard_id = card;
  insert into res values ('owner sees own entry','1',n::text);

  -- REGRESSION: PostgREST always adds RETURNING, so the SELECT policy has to
  -- pass on the brand-new row. A policy that only calls a STABLE helper which
  -- re-queries the same table cannot see it, and the insert is rejected.
  -- This is the bug fixed by 05-fix-insert-returning.sql.
  begin
    insert into public.sc_user_scorecards(owner,template_id) values (a,tpl) returning id into tmp;
    insert into res values ('owner INSERT..RETURNING card','OK','OK');
  exception when others then
    get stacked diagnostics msg = message_text;
    insert into res values ('owner INSERT..RETURNING card','OK','FAIL: '||msg);
  end;
  begin
    insert into public.sc_user_scorecard_items(user_scorecard_id,library_item_id,category_id,frequency)
      values (card,lib2,cat,'weekly') returning id into tmp;
    insert into res values ('owner INSERT..RETURNING item','OK','OK');
  exception when others then
    get stacked diagnostics msg = message_text;
    insert into res values ('owner INSERT..RETURNING item','OK','FAIL: '||msg);
  end;
  begin
    insert into public.sc_entries(user_scorecard_id,user_scorecard_item_id,period_start,value_bool)
      values (card,tmp,(date_trunc('month',current_date)-interval '1 month')::date,true) returning id into tmp;
    insert into res values ('owner INSERT..RETURNING entry','OK','OK');
  exception when others then
    get stacked diagnostics msg = message_text;
    insert into res values ('owner INSERT..RETURNING entry','OK','FAIL: '||msg);
  end;

  -- =================================================================
  -- B sees nothing
  -- =================================================================
  perform set_config('request.jwt.claims', json_build_object('sub',b,'role','authenticated')::text, true);
  select count(*) into n from public.sc_user_scorecards where id = card;
  insert into res values ('stranger sees card','0',n::text);
  select count(*) into n from public.sc_user_scorecard_items where user_scorecard_id = card;
  insert into res values ('stranger sees items','0',n::text);
  select count(*) into n from public.sc_entries where user_scorecard_id = card;
  insert into res values ('stranger sees entries','0',n::text);

  -- =================================================================
  -- 6.1 share to view
  -- =================================================================
  reset role;
  insert into public.sc_shares(user_scorecard_id, shared_by, shared_with_user_id, access)
    values (card, a, b, 'view');
  set local role authenticated;
  perform set_config('request.jwt.claims', json_build_object('sub',b,'role','authenticated')::text, true);
  select count(*) into n from public.sc_user_scorecards where id = card;
  insert into res values ('view-share: sees card','1',n::text);
  update public.sc_entries set value_bool = false where user_scorecard_id = card;
  get diagnostics n = row_count;
  insert into res values ('view-share: rows it can edit','0',n::text);

  -- =================================================================
  -- 6.2 share to co-own
  -- =================================================================
  reset role;
  update public.sc_shares set access='edit' where user_scorecard_id=card and shared_with_user_id=b;
  set local role authenticated;
  perform set_config('request.jwt.claims', json_build_object('sub',b,'role','authenticated')::text, true);
  update public.sc_entries set value_bool = false where user_scorecard_id = card;
  get diagnostics n = row_count;
  insert into res values ('edit-share: can edit entries','2',n::text);

  -- =================================================================
  -- 6.3 roster — pending grants nothing, accepted grants read only
  -- =================================================================
  reset role;
  delete from public.sc_shares where user_scorecard_id = card;
  insert into public.sc_rosters(owner, template_id, member_user_id, status)
    values (b, tpl, a, 'pending');
  set local role authenticated;
  perform set_config('request.jwt.claims', json_build_object('sub',b,'role','authenticated')::text, true);
  select count(*) into n from public.sc_user_scorecards where id = card;
  insert into res values ('roster pending: sees card','0',n::text);

  reset role;
  update public.sc_rosters set status='accepted' where owner=b and member_user_id=a;
  set local role authenticated;
  perform set_config('request.jwt.claims', json_build_object('sub',b,'role','authenticated')::text, true);
  select count(*) into n from public.sc_user_scorecards where id = card;
  insert into res values ('roster accepted: sees card','1',n::text);
  update public.sc_entries set value_bool = true where user_scorecard_id = card;
  get diagnostics n = row_count;
  insert into res values ('roster accepted: rows it can edit','0',n::text);

  -- =================================================================
  -- template content
  -- =================================================================
  select count(*) into n from public.sc_library_items;
  insert into res values ('any user reads library','241',n::text);

  -- =================================================================
  -- the time tracker is untouched
  -- =================================================================
  reset role;
  select count(*) into n from pg_policies where schemaname='public'
    and tablename in ('profiles','channels','sessions','plans','dayplans')
    and policyname like 'sc%';
  insert into res values ('policies added to tracker tables','0',n::text);

  -- =================================================================
  -- anon must not be able to execute any sc_ function
  -- (04-fix-function-grants.sql)
  -- =================================================================
  select count(*) into n from pg_proc p join pg_namespace ns on ns.oid=p.pronamespace
   where ns.nspname='public' and p.proname like 'sc\_%'
     and has_function_privilege('anon', p.oid, 'EXECUTE');
  insert into res values ('sc_ functions anon can execute','0',n::text);
end $t$;

select step, expected, got,
       case when expected = got then 'PASS' else 'FAIL' end as result
from res;

rollback;
