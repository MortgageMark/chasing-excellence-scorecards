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
-- Content: Mark's Sales & Marketing worksheet (2 categories, 31 items).
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
  ('marketing', 'Marketing', 0),
  ('sales', 'Sales', 1)
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
  ('marketing', 'social-posts-3-ig-1-linkedin-google-review-post', 'Social Posts (3 IG, 1 LinkedIn, Google Review Post)', 'daily', true, 0),
  ('marketing', 'youtube-post', 'YouTube Post', 'daily', true, 1),
  ('marketing', 'marketing-calendar-review-execute', 'Marketing Calendar - Review & Execute', 'daily', true, 2),
  ('marketing', 'fu-on-google-review-requests', 'FU on Google Review Requests', 'daily', true, 3),
  ('marketing', 'google-reviews', 'Google Reviews', 'daily', true, 4),
  ('marketing', 'dtr', 'DTR', 'weekly', true, 5),
  ('marketing', 'eoa', 'EOA', 'weekly', true, 6),
  ('marketing', 'lal-video-blog-and-fliers', 'LAL: video, blog, and fliers', 'weekly', true, 7),
  ('marketing', 'monday-marketing-email-mme', 'Monday Marketing Email (MME)', 'weekly', true, 8),
  ('marketing', 'send-tu-note-and-lotto-ticket-to-every-referral-source', 'Send TU note (and lotto ticket) to every referral source', 'weekly', true, 9),
  ('marketing', 'spend-100-on-unreasonable-hospitality', 'Spend $100 on Unreasonable Hospitality', 'weekly', true, 10),
  ('marketing', 'weekly-market-update', 'Weekly Market Update', 'weekly', true, 11),
  ('marketing', 'whale-campaign', 'Whale Campaign', 'weekly', true, 12),
  ('marketing', 'weekend-warrior-sms', 'Weekend Warrior SMS', 'weekly', true, 13),
  ('marketing', 'lfth', 'LFTH', 'monthly', true, 14),
  ('marketing', 'cheesy-gifts', 'Cheesy Gifts', 'monthly', true, 15),
  ('marketing', 'events-12-l-l-6-hh', 'Events (12 L&L / 6 HH)', 'monthly', true, 16),
  ('marketing', 'newsletter-to-clients', 'Newsletter to Clients', 'monthly', true, 17),
  ('marketing', 'snail-mail-to-database', 'Snail mail to database', 'monthly', true, 18),
  ('marketing', 'vip-gifts', 'VIP Gifts', 'monthly', true, 19),
  ('marketing', 'client-appreciation-events-x-2-per-year', 'Client Appreciation Events x 2 per year', 'semiannual', true, 20),
  ('marketing', '12-days-of-xmas-with-sponsor-each-day', '12 Days of Xmas (with sponsor each day)', 'annual', true, 21),
  ('sales', 'time-tracker-80', 'Time Tracker 80%', 'daily', true, 0),
  ('sales', 'activity-tracker', 'Activity Tracker', 'daily', true, 1),
  ('sales', 'theme-day-calls', 'Theme Day Calls', 'daily', true, 2),
  ('sales', 'green-time-4-hr-per-day', 'Green Time: 4/hr per day', 'weekly', true, 3),
  ('sales', 'gold-time-1-hr-per-day', 'Gold Time: 1/hr per day', 'weekly', true, 4),
  ('sales', 'new-realtor-3-per-week', 'New Realtor: 3 per week', 'weekly', true, 5),
  ('sales', 'handwritten-card', 'Handwritten Card', 'weekly', true, 6),
  ('sales', 'call-past-clients', 'Call Past Clients', 'monthly', true, 7),
  ('sales', 'annual-client-reviews', 'Annual Client Reviews', 'monthly', true, 8)
) as v(cat_code, code, label, freq, is_default_on, sort_order)
  on v.cat_code = c.code
on conflict (category_id, code) do update set
  label = excluded.label, default_frequency = excluded.default_frequency,
  is_default_on = excluded.is_default_on, sort_order = excluded.sort_order,
  is_active = true, updated_at = now();

-- ---------------------------------------------------------------------
-- Retire the first-draft placeholders. Items are deactivated (never
-- deleted, so any scorecard already started keeps working); categories
-- nothing points at are removed.
-- ---------------------------------------------------------------------
update public.sc_library_items i set is_active = false, updated_at = now()
from public.sc_categories c
join public.sc_templates t on t.id = c.template_id and t.slug = 'sales-marketing'
where i.category_id = c.id
  and i.code in ('make-new-contacts','review-pipeline','return-leads-same-day',
                 'follow-up-past-clients','post-on-social','send-newsletter',
                 'contact-referral-partners','referral-partner-meeting');

delete from public.sc_categories c
using public.sc_templates t
where t.id = c.template_id and t.slug = 'sales-marketing'
  and c.code in ('prospecting','follow-up','referrals')
  and not exists (select 1 from public.sc_user_scorecard_items u where u.category_id = c.id);

-- Verify: expect Marketing 22 / Sales 9
select c.code, count(*) filter (where i.is_active) as items
from public.sc_categories c
join public.sc_templates t on t.id = c.template_id and t.slug = 'sales-marketing'
left join public.sc_library_items i on i.category_id = c.id
group by c.code, c.sort_order order by c.sort_order;
