-- =====================================================================
-- Chasing Excellence Scorecards — 06 SEED: Sales & Marketing
--
-- A second template, built exactly like Life Balance (03). Idempotent:
-- `code` is the conflict key, so re-running after you edit a label
-- updates the row instead of duplicating it.
--
-- HOW TO ADD QUESTIONS
--   Add a row to the items list below:
--     ('category-code', 'unique-item-code', 'Question / habit text',
--      'daily|weekly|monthly|quarterly|semiannual|annual', is_default_on, sort_order)
--   Then re-run this file in the Supabase SQL editor. No app change needed.
--   To add a category, add a row to the categories list. The radar chart
--   needs at least 3 categories with selected items.
--
-- The items below are PLACEHOLDERS to replace with your own.
-- =====================================================================

insert into public.sc_templates
  (slug, name, description, score_label, scoring_mode,
   allows_multi_instance, is_published, access_tier, sort_order)
values
  ('sales-marketing', 'Sales & Marketing Scorecard',
   'Track the sales and marketing habits that grow your business, and see where you are strong and where you are slipping.',
   'Growth', 'binary', false, true, 'free', 1)
on conflict (slug) do update set
  name = excluded.name, description = excluded.description,
  score_label = excluded.score_label, scoring_mode = excluded.scoring_mode,
  allows_multi_instance = excluded.allows_multi_instance,
  is_published = excluded.is_published, access_tier = excluded.access_tier,
  sort_order = excluded.sort_order, updated_at = now();

insert into public.sc_categories (template_id, code, name, sort_order)
select t.id, v.code, v.name, v.sort_order
from public.sc_templates t
cross join (values
  ('prospecting', 'Prospecting', 0),
  ('follow-up', 'Follow-Up', 1),
  ('marketing', 'Marketing', 2),
  ('referrals', 'Referral Partners', 3)
) as v(code, name, sort_order)
where t.slug = 'sales-marketing'
on conflict (template_id, code) do update set
  name = excluded.name, sort_order = excluded.sort_order, updated_at = now();

insert into public.sc_library_items
  (category_id, code, label, default_frequency, is_default_on, sort_order)
select c.id, v.code, v.label, v.freq::sc_frequency, v.is_default_on, v.sort_order
from public.sc_categories c
join public.sc_templates t on t.id = c.template_id and t.slug = 'sales-marketing'
join (values
  -- Prospecting
  ('prospecting', 'make-new-contacts', 'Make new prospecting contacts', 'daily', true, 0),
  ('prospecting', 'review-pipeline', 'Review my pipeline', 'weekly', true, 1),
  -- Follow-Up
  ('follow-up', 'return-leads-same-day', 'Return every lead the same day', 'daily', true, 0),
  ('follow-up', 'follow-up-past-clients', 'Follow up with past clients', 'monthly', true, 1),
  -- Marketing
  ('marketing', 'post-on-social', 'Post on social media', 'weekly', true, 0),
  ('marketing', 'send-newsletter', 'Send my newsletter', 'monthly', true, 1),
  -- Referral Partners
  ('referrals', 'contact-referral-partners', 'Contact a referral partner', 'weekly', true, 0),
  ('referrals', 'referral-partner-meeting', 'Meet with a referral partner', 'monthly', false, 1)
) as v(cat_code, code, label, freq, is_default_on, sort_order)
  on v.cat_code = c.code
on conflict (category_id, code) do update set
  label = excluded.label, default_frequency = excluded.default_frequency,
  is_default_on = excluded.is_default_on, sort_order = excluded.sort_order,
  updated_at = now();
