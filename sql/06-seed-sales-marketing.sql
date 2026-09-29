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
-- Content: Mark's Sales & Marketing worksheet (6 categories, yes/no questions).
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
  ('sales-activity', 'Sales Activity', 0),
  ('time-management', 'Time Management', 1),
  ('realtor-partners', 'Realtor Partners & Referrals', 2),
  ('database', 'Database & Past Clients', 3),
  ('online-presence', 'Online Presence & Reviews', 4),
  ('personal-development', 'Personal Development', 5)
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
  ('sales-activity', 'did-you-complete-your-activity-tracker-greatness-tracker-tod', 'Did you complete your Activity Tracker (Greatness Tracker) today?', 'daily', true, 0),
  ('sales-activity', 'did-you-hit-80-on-your-time-tracker-today', 'Did you hit 80% on your Time Tracker today?', 'daily', true, 1),
  ('sales-activity', 'did-you-make-all-your-theme-day-calls-today', 'Did you make all your Theme Day calls today?', 'daily', true, 2),
  ('sales-activity', 'did-you-check-the-mbs-highway-market-update-today', 'Did you check the MBS Highway market update today?', 'daily', true, 3),
  ('time-management', 'did-you-spend-20-hours-in-green-time-this-week', 'Did you spend 20 hours in Green Time this week?', 'weekly', true, 0),
  ('time-management', 'did-you-spend-5-hours-in-gold-time-this-week', 'Did you spend 5 hours in Gold Time this week?', 'weekly', true, 1),
  ('time-management', 'did-you-spend-10-hours-on-recruiting-this-week', 'Did you spend 10 hours on Recruiting this week?', 'weekly', true, 2),
  ('time-management', 'did-you-spend-2-hours-working-on-your-business-this-week', 'Did you spend 2 hours working "on" your business this week?', 'weekly', true, 3),
  ('time-management', 'did-you-work-50-total-hours-this-week', 'Did you work 50 total hours this week?', 'weekly', true, 4),
  ('realtor-partners', 'did-you-meet-3-new-realtors-this-week', 'Did you meet 3 new Realtors this week?', 'weekly', true, 0),
  ('realtor-partners', 'did-you-email-your-realtors-the-monday-marketing-email-mme', 'Did you email your Realtors the Monday Marketing Email (MME)?', 'weekly', true, 1),
  ('realtor-partners', 'did-you-email-your-realtors-the-weekly-market-update-video', 'Did you email your Realtors the weekly market update video?', 'weekly', true, 2),
  ('realtor-partners', 'did-you-send-your-realtors-the-weekly-program-update-lal-vid', 'Did you send your Realtors the weekly program update (LAL: video, blog, and fliers)?', 'weekly', true, 3),
  ('realtor-partners', 'did-you-send-a-thank-you-note-and-lotto-ticket-to-every-refe', 'Did you send a thank-you note (and lotto ticket) to every referral source?', 'weekly', true, 4),
  ('realtor-partners', 'did-you-spend-100-on-unreasonable-hospitality', 'Did you spend $100 on Unreasonable Hospitality?', 'weekly', true, 5),
  ('realtor-partners', 'did-you-send-your-5-handwritten-cards-this-week', 'Did you send your 5 handwritten cards this week?', 'weekly', true, 6),
  ('database', 'did-you-review-and-update-your-dtr-list-this-week', 'Did you review and update your DTR list this week?', 'weekly', true, 0),
  ('database', 'did-you-send-your-database-an-evidence-of-awesomeness-eoa', 'Did you send your database an Evidence of Awesomeness (EOA)?', 'weekly', true, 1),
  ('database', 'did-you-run-your-whale-campaign-this-week', 'Did you run your Whale Campaign this week?', 'weekly', true, 2),
  ('database', 'did-you-send-the-weekend-warrior-sms-this-week', 'Did you send the Weekend Warrior SMS this week?', 'weekly', true, 3),
  ('database', 'did-you-send-cheesy-gifts-this-month', 'Did you send Cheesy Gifts this month?', 'monthly', true, 4),
  ('database', 'did-you-send-vip-gifts-this-month', 'Did you send VIP Gifts this month?', 'monthly', true, 5),
  ('database', 'did-you-send-the-newsletter-to-clients-this-month', 'Did you send the newsletter to clients this month?', 'monthly', true, 6),
  ('database', 'did-you-send-snail-mail-to-your-database-this-month', 'Did you send snail mail to your database this month?', 'monthly', true, 7),
  ('database', 'did-you-call-your-past-clients-two-letters-of-the-alphabet-t', 'Did you call your past clients (two letters of the alphabet) this month?', 'monthly', true, 8),
  ('database', 'did-you-do-your-annual-client-reviews-this-month', 'Did you do your Annual Client Reviews this month?', 'monthly', true, 9),
  ('database', 'did-you-hold-your-events-this-month-12-l-l-6-hh-per-year', 'Did you hold your events this month (12 L&L / 6 HH per year)?', 'monthly', true, 10),
  ('database', 'did-you-send-a-letter-from-the-heart-lfth-this-quarter', 'Did you send a Letter From The Heart (LFTH) this quarter?', 'quarterly', true, 11),
  ('database', 'did-you-hold-your-client-appreciation-event-this-half-year-2', 'Did you hold your Client Appreciation Event this half-year (2 per year)?', 'semiannual', true, 12),
  ('database', 'did-you-run-the-12-days-of-xmas-with-a-sponsor-each-day', 'Did you run the 12 Days of Xmas with a sponsor each day?', 'annual', true, 13),
  ('online-presence', 'did-you-post-on-social-3-ig-1-linkedin-google-review-post-to', 'Did you post on social (3 IG, 1 LinkedIn, Google Review post) today?', 'daily', true, 0),
  ('online-presence', 'did-you-do-your-social-post-today', 'Did you do your Social: Post today?', 'daily', true, 1),
  ('online-presence', 'did-you-do-your-social-comments-today-25-x-4', 'Did you do your Social: Comments today (25 x 4)?', 'daily', true, 2),
  ('online-presence', 'did-you-do-your-social-dms-today-25-x-4', 'Did you do your Social: DMs today (25 x 4)?', 'daily', true, 3),
  ('online-presence', 'did-you-post-on-youtube-today', 'Did you post on YouTube today?', 'daily', true, 4),
  ('online-presence', 'did-you-review-and-execute-your-marketing-calendar-today', 'Did you review and execute your marketing calendar today?', 'daily', true, 5),
  ('online-presence', 'is-your-calendar-written-with-no-white-space', 'Is your calendar written with no white space?', 'daily', true, 6),
  ('online-presence', 'is-your-calendar-accuracy-90-or-better', 'Is your calendar accuracy 90% or better?', 'daily', true, 7),
  ('online-presence', 'did-you-ask-every-lead-and-realtor-you-work-with-for-a-googl', 'Did you ask every lead and Realtor you work with for a Google Review?', 'daily', true, 8),
  ('online-presence', 'did-you-follow-up-on-your-google-review-requests', 'Did you follow up on your Google Review requests?', 'daily', true, 9),
  ('personal-development', 'did-you-journal-for-your-business-today', 'Did you journal for your business today?', 'daily', true, 0),
  ('personal-development', 'did-you-read-chrisman-nrep-and-mortgage-daily-today', 'Did you read Chrisman, NREP and Mortgage Daily today?', 'daily', true, 1),
  ('personal-development', 'were-you-coached-twice-this-month', 'Were you coached twice this month?', 'monthly', true, 2),
  ('personal-development', 'did-you-coach-someone-this-month', 'Did you coach someone this month?', 'monthly', true, 3)
) as v(cat_code, code, label, freq, is_default_on, sort_order)
  on v.cat_code = c.code
on conflict (category_id, code) do update set
  label = excluded.label, default_frequency = excluded.default_frequency,
  is_default_on = excluded.is_default_on, sort_order = excluded.sort_order,
  is_active = true, updated_at = now();

-- ---------------------------------------------------------------------
-- Retire anything from earlier drafts. Items no longer in the list above
-- are deactivated (never deleted, so a scorecard already started keeps
-- working); categories from earlier drafts that nothing points at are
-- removed.
-- ---------------------------------------------------------------------
update public.sc_library_items i set is_active = false, updated_at = now()
from public.sc_categories c
join public.sc_templates t on t.id = c.template_id and t.slug = 'sales-marketing'
where i.category_id = c.id and c.code not in ('sales-activity','time-management','realtor-partners','database','online-presence','personal-development');

delete from public.sc_categories c
using public.sc_templates t
where t.id = c.template_id and t.slug = 'sales-marketing'
  and c.code not in ('sales-activity','time-management','realtor-partners','database','online-presence','personal-development')
  and not exists (select 1 from public.sc_user_scorecard_items u where u.category_id = c.id);

-- Verify: expect 44 active items across 6 categories
select c.code, count(*) filter (where i.is_active) as items
from public.sc_categories c
join public.sc_templates t on t.id = c.template_id and t.slug = 'sales-marketing'
left join public.sc_library_items i on i.category_id = c.id
group by c.code, c.sort_order order by c.sort_order;
