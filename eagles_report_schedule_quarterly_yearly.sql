-- EAGLES: schedule QUARTERLY and YEARLY (Indian financial year) reports with PDFs.
-- Run once in Supabase SQL Editor. Times are UTC (IST = UTC + 5:30).
--   Quarterly: 1st of Jan/Apr/Jul/Oct at 7:15 AM IST -> reports the quarter that just ended
--              (Q1 Apr-Jun, Q2 Jul-Sep, Q3 Oct-Dec, Q4 Jan-Mar)
--   Yearly   : 1st April at 7:30 AM IST -> reports the financial year just ended (Apr-Mar)
-- Weekly (Mon 7:00 IST) and monthly (1st, 7:00 IST) jobs already exist; they now also attach PDFs.

select cron.unschedule(jobid) from cron.job where jobname in ('ea-quarterly-report','ea-yearly-report');

select cron.schedule('ea-quarterly-report', '45 1 1 1,4,7,10 *', $$
  select net.http_post(
    url := 'https://cnvxmpnudgjwdoccvqbk.supabase.co/functions/v1/send-report',
    headers := jsonb_build_object('Content-Type','application/json','x-report-secret',(select value from public.ea_push_config where key='fn_secret')),
    body := '{"period":"quarterly"}'::jsonb, timeout_milliseconds := 60000);
$$);

select cron.schedule('ea-yearly-report', '0 2 1 4 *', $$
  select net.http_post(
    url := 'https://cnvxmpnudgjwdoccvqbk.supabase.co/functions/v1/send-report',
    headers := jsonb_build_object('Content-Type','application/json','x-report-secret',(select value from public.ea_push_config where key='fn_secret')),
    body := '{"period":"yearly"}'::jsonb, timeout_milliseconds := 60000);
$$);

select jobname, schedule from cron.job where jobname like 'ea-%report' order by jobname;
