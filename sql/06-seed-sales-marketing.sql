-- =====================================================================
-- Chasing Excellence Scorecards — 06 SEED: Sales & Marketing
--
-- A second template, built exactly like Life Balance (03). Idempotent:
-- `code` is the conflict key, so re-running after you edit a label
-- updates the row instead of duplicating it.
--
-- HOW TO ADD QUESTIONS
--   Add a row to the items list below:
--     ('category-code', 'unique-item-code', 'Full question',
--      'Short checklist text', 'weekly|monthly|quarterly|semiannual|annual',
--      is_default_on, sort_order)
--   The short text is what shows on the check-in checklist; the full question
--   shows under it on the Items screen.
--   Then re-run this file in the Supabase SQL editor. No app change needed.
--   To add a category, add a row to the categories list. The radar chart
--   needs at least 3 categories with selected items.
--
-- Content: Mark's Sales & Marketing worksheet (5 categories, yes/no questions, weekly check-in).
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
  ('business-development', 'Business Development', 0),
  ('time-management', 'Time Management', 1),
  ('sales-activity', 'Sales Activity', 2),
  ('marketing', 'Marketing', 3),
  ('online-presence', 'Online Presence & Reviews', 4)
) as v(code, name, sort_order)
where t.slug = 'sales-marketing'
on conflict (template_id, code) do update set
  name = excluded.name, sort_order = excluded.sort_order, updated_at = now();

-- The item list goes into a temp table first so the same list drives both
-- the upsert and the clean-up of anything you have since removed.
drop table if exists _sm_items;
create temp table _sm_items (
  cat_code text, code text, label text, short_label text, freq text, is_default_on boolean, sort_order int);
insert into _sm_items values
  ('business-development', 'do-you-have-a-business-plan', 'Do you have a business plan?', 'Do you have a business plan?', 'weekly', true, 0),
  ('business-development', 'did-you-review-your-business-plan', 'Did you review your business plan?', 'Did you review your business plan?', 'weekly', true, 1),
  ('business-development', 'do-you-do-your-business-journal-daily', 'Do you do your business journal daily?', 'Do you do your business journal daily?', 'weekly', true, 2),
  ('business-development', 'did-you-read-chrisman-nrep-mortgage-daily-and-the-mbs-highwa', 'Did you read Chrisman, NREP, Mortgage Daily and the MBS Highway market update daily?', 'Did you read Chrisman, NREP, Mortgage Daily and the MBS Highway market update daily?', 'weekly', true, 3),
  ('business-development', 'did-you-meet-with-your-coach-or-accountability-group', 'Did you meet with your coach or accountability group?', 'Did you meet with your coach or accountability group?', 'weekly', true, 4),
  ('time-management', 'do-you-track-your-time-daily', 'Do you track your time daily?', 'Do you track your time daily?', 'weekly', true, 0),
  ('time-management', 'did-you-print-out-your-calendar-every-day', 'Did you print out your calendar every day?', 'Did you print out your calendar every day?', 'weekly', true, 1),
  ('time-management', 'did-you-hit-80-on-your-time-tracker', 'Did you hit 80% on your Time Tracker?', 'Did you hit 80% on your Time Tracker?', 'weekly', true, 2),
  ('time-management', 'was-your-calendar-full-with-no-white-space-all-week', 'Was your calendar full, with no white space, all week?', 'Was your calendar full, with no white space, all week?', 'weekly', true, 3),
  ('time-management', 'did-you-spend-20-hours-in-green-time', 'Did you spend 20 hours in Green Time?', 'Did you spend 20 hours in Green Time?', 'weekly', true, 4),
  ('time-management', 'did-you-spend-5-hours-in-gold-time', 'Did you spend 5 hours in Gold Time?', 'Did you spend 5 hours in Gold Time?', 'weekly', true, 5),
  ('time-management', 'did-you-spend-10-hours-on-recruiting', 'Did you spend 10 hours on Recruiting?', 'Did you spend 10 hours on Recruiting?', 'weekly', true, 6),
  ('time-management', 'did-you-spend-2-hours-working-on-your-business', 'Did you spend 2 hours working "on" your business?', 'Did you spend 2 hours working "on" your business?', 'weekly', true, 7),
  ('time-management', 'did-you-work-at-least-40-hours', 'Did you work at least 40 hours?', 'Did you work at least 40 hours?', 'weekly', true, 8),
  ('time-management', 'did-you-work-no-more-than-50-hours', 'Did you work no more than 50 hours?', 'Did you work no more than 50 hours?', 'weekly', true, 9),
  ('sales-activity', 'did-you-complete-your-activity-tracker', 'Did you complete your Activity Tracker?', 'Did you complete your Activity Tracker?', 'weekly', true, 0),
  ('sales-activity', 'did-you-hit-at-least-50-talk-tos', 'Did you hit (at least) 50 talk-tos?', 'Did you hit (at least) 50 talk-tos?', 'weekly', true, 1),
  ('sales-activity', 'did-you-leave-at-least-50-voicemails', 'Did you leave (at least) 50 voicemails?', 'Did you leave (at least) 50 voicemails?', 'weekly', true, 2),
  ('sales-activity', 'did-you-have-at-least-10-face-to-face-appointments', 'Did you have (at least) 10 face-to-face appointments?', 'Did you have (at least) 10 face-to-face appointments?', 'weekly', true, 3),
  ('sales-activity', 'did-you-meet-at-least-3-new-realtors', 'Did you meet (at least) 3 new Realtors?', 'Did you meet (at least) 3 new Realtors?', 'weekly', true, 4),
  ('sales-activity', 'did-you-make-all-your-theme-day-calls-every-day', 'Did you make all your Theme Day calls every day?', 'Did you make all your Theme Day calls every day?', 'weekly', true, 5),
  ('sales-activity', 'did-you-ask-for-leads-in-every-conversation', 'Did you ask for leads in every conversation?', 'Did you ask for leads in every conversation?', 'weekly', true, 6),
  ('sales-activity', 'did-you-get-10-new-leads', 'Did you get 10 new leads?', 'Did you get 10 new leads?', 'weekly', true, 7),
  ('sales-activity', 'did-you-attend-at-least-one-networking-event', 'Did you attend at least one networking event?', 'Did you attend at least one networking event?', 'weekly', true, 8),
  ('sales-activity', 'did-you-complete-5-pre-quals', 'Did you complete 5 pre-quals?', 'Did you complete 5 pre-quals?', 'weekly', true, 9),
  ('sales-activity', 'did-you-have-5-closings-actual-closings', 'Did you have 5 closings? (actual closings)', 'Did you have 5 closings? (actual closings)', 'weekly', true, 10),
  ('sales-activity', 'did-you-start-7-deals-loan-apps-with-contracts', 'Did you start 7 deals? (loan apps with contracts)', 'Did you start 7 deals? (loan apps with contracts)', 'weekly', true, 11),
  ('marketing', 'did-you-email-your-realtors-the-monday-marketing-email-mme', 'Did you email your Realtors the Monday Marketing Email (MME)?', 'Did you email your Realtors the Monday Marketing Email (MME)?', 'weekly', true, 0),
  ('marketing', 'did-you-email-your-realtors-the-weekly-market-update-video', 'Did you email your Realtors the weekly market update video?', 'Did you email your Realtors the weekly market update video?', 'weekly', true, 1),
  ('marketing', 'did-you-send-your-realtors-the-weekly-program-update-lal-vid', 'Did you send your Realtors the weekly program update (LAL: video, blog, and fliers)?', 'Did you send your Realtors the weekly program update (LAL: video, blog, and fliers)?', 'weekly', true, 2),
  ('marketing', 'did-you-send-a-thank-you-note-and-lotto-ticket-to-every-refe', 'Did you send a thank-you note (and lotto ticket) to every referral source?', 'Did you send a thank-you note (and lotto ticket) to every referral source?', 'weekly', true, 3),
  ('marketing', 'did-you-spend-100-on-unreasonable-hospitality', 'Did you spend $100 on Unreasonable Hospitality?', 'Did you spend $100 on Unreasonable Hospitality?', 'weekly', true, 4),
  ('marketing', 'did-you-send-5-handwritten-cards', 'Did you send 5 handwritten cards?', 'Did you send 5 handwritten cards?', 'weekly', true, 5),
  ('marketing', 'did-you-review-and-update-your-database-categories', 'Did you review and update your database categories?', 'Did you review and update your database categories?', 'weekly', true, 6),
  ('marketing', 'did-you-send-your-database-an-evidence-of-awesomeness-eoa', 'Did you send your database an Evidence of Awesomeness (EOA)?', 'Did you send your database an Evidence of Awesomeness (EOA)?', 'weekly', true, 7),
  ('marketing', 'did-you-run-your-whale-campaign', 'Did you run your Whale Campaign?', 'Did you run your Whale Campaign?', 'weekly', true, 8),
  ('marketing', 'did-you-send-your-friday-weekend-warrior-text-sms', 'Did you send your Friday Weekend Warrior text (SMS)?', 'Did you send your Friday Weekend Warrior text (SMS)?', 'weekly', true, 9),
  ('marketing', 'did-you-send-cheesy-gifts-this-month', 'Did you send Cheesy Gifts this month?', 'Did you send Cheesy Gifts this month?', 'monthly', true, 10),
  ('marketing', 'did-you-send-vip-gifts-this-month', 'Did you send VIP Gifts this month?', 'Did you send VIP Gifts this month?', 'monthly', true, 11),
  ('marketing', 'did-you-send-the-newsletter-to-clients-this-month', 'Did you send the newsletter to clients this month?', 'Did you send the newsletter to clients this month?', 'monthly', true, 12),
  ('marketing', 'did-you-send-snail-mail-to-your-database-this-month', 'Did you send snail mail to your database this month?', 'Did you send snail mail to your database this month?', 'monthly', true, 13),
  ('marketing', 'did-you-call-your-past-clients-two-letters-of-the-alphabet-t', 'Did you call your past clients (two letters of the alphabet) this month?', 'Did you call your past clients (two letters of the alphabet) this month?', 'monthly', true, 14),
  ('marketing', 'did-you-do-your-annual-client-reviews-this-month', 'Did you do your Annual Client Reviews this month?', 'Did you do your Annual Client Reviews this month?', 'monthly', true, 15),
  ('marketing', 'did-you-host-a-lunch-and-learn-this-month', 'Did you host a lunch and learn this month?', 'Did you host a lunch and learn this month?', 'monthly', true, 16),
  ('marketing', 'did-you-host-a-happy-hour-this-month', 'Did you host a happy hour this month?', 'Did you host a happy hour this month?', 'monthly', true, 17),
  ('marketing', 'did-you-send-a-letter-from-the-heart-lfth-this-quarter', 'Did you send a Letter From The Heart (LFTH) this quarter?', 'Did you send a Letter From The Heart (LFTH) this quarter?', 'quarterly', true, 18),
  ('marketing', 'did-you-hold-your-client-appreciation-event-2-per-year', 'Did you hold your Client Appreciation Event (2 per year)?', 'Did you hold your Client Appreciation Event (2 per year)?', 'semiannual', true, 19),
  ('marketing', 'did-you-run-the-12-days-of-xmas-with-a-sponsor-each-day', 'Did you run the 12 Days of Xmas with a sponsor each day?', 'Did you run the 12 Days of Xmas with a sponsor each day?', 'annual', true, 20),
  ('online-presence', 'did-you-make-3-social-posts', 'Did you make 3 social posts?', 'Did you make 3 social posts?', 'weekly', true, 0),
  ('online-presence', 'did-you-do-your-social-comments-25-x-4', 'Did you do your Social: Comments (25 x 4)?', 'Did you do your Social: Comments (25 x 4)?', 'weekly', true, 1),
  ('online-presence', 'did-you-do-your-social-dms-25-x-4', 'Did you do your Social: DMs (25 x 4)?', 'Did you do your Social: DMs (25 x 4)?', 'weekly', true, 2),
  ('online-presence', 'did-you-post-one-youtube-video', 'Did you post one YouTube video?', 'Did you post one YouTube video?', 'weekly', true, 3),
  ('online-presence', 'did-you-spend-5-hours-making-content', 'Did you spend 5 hours making content?', 'Did you spend 5 hours making content?', 'weekly', true, 4),
  ('online-presence', 'did-you-review-and-execute-your-marketing-calendar', 'Did you review and execute your marketing calendar?', 'Did you review and execute your marketing calendar?', 'weekly', true, 5),
  ('online-presence', 'did-you-ask-every-lead-and-realtor-you-work-with-for-a-googl', 'Did you ask every lead and Realtor you work with for a Google Review?', 'Did you ask every lead and Realtor you work with for a Google Review?', 'weekly', true, 6),
  ('online-presence', 'did-you-follow-up-on-your-google-review-requests', 'Did you follow up on your Google Review requests?', 'Did you follow up on your Google Review requests?', 'weekly', true, 7);

insert into public.sc_library_items
  (category_id, code, label, short_label, default_frequency, is_default_on, sort_order)
select c.id, v.code, v.label, v.short_label, v.freq::sc_frequency, v.is_default_on, v.sort_order
from public.sc_categories c
join public.sc_templates t on t.id = c.template_id and t.slug = 'sales-marketing'
join _sm_items v on v.cat_code = c.code
on conflict (category_id, code) do update set
  label = excluded.label, short_label = excluded.short_label,
  default_frequency = excluded.default_frequency,
  is_default_on = excluded.is_default_on, sort_order = excluded.sort_order,
  is_active = true, updated_at = now();

-- ---------------------------------------------------------------------
-- Clean-up. Items no longer in the list are deactivated (never deleted, so
-- a scorecard already started keeps working). Categories no longer in the
-- list are removed if nothing points at them.
-- ---------------------------------------------------------------------
update public.sc_library_items i set is_active = false, updated_at = now()
from public.sc_categories c
join public.sc_templates t on t.id = c.template_id and t.slug = 'sales-marketing'
where i.category_id = c.id and i.is_active
  and not exists (select 1 from _sm_items v where v.cat_code = c.code and v.code = i.code);

delete from public.sc_categories c
using public.sc_templates t
where t.id = c.template_id and t.slug = 'sales-marketing'
  and c.code not in ('business-development','time-management','sales-activity','marketing','online-presence')
  and not exists (select 1 from public.sc_user_scorecard_items u where u.category_id = c.id);

drop table if exists _sm_items;

-- Verify: expect 56 active items across 5 categories
select c.code, count(*) filter (where i.is_active) as items
from public.sc_categories c
join public.sc_templates t on t.id = c.template_id and t.slug = 'sales-marketing'
left join public.sc_library_items i on i.category_id = c.id
group by c.code, c.sort_order order by c.sort_order;
