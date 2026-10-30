-- Production query: daily passed-question summary for after-class Words & Sentences.
WITH base AS (
  SELECT
    TIMESTAMP_MICROS(event_timestamp) AS event_ts,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key='event_id') AS event_id,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key='uid') AS uid,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key='content_id') AS content_id,
    COALESCE(
      (SELECT value.string_value FROM UNNEST(event_params) WHERE key='content_index'),
      CAST((SELECT value.int_value FROM UNNEST(event_params) WHERE key='content_index') AS STRING)
    ) AS content_index,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key='scene') AS scene,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key='type') AS course_type,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key='result') AS result
  FROM `dino-english-497507.analytics_538991439.events_*`
  WHERE _TABLE_SUFFIX BETWEEN FORMAT_DATE('%Y%m%d', @scan_start_date)
    AND FORMAT_DATE('%Y%m%d', DATE_SUB(@end_date, INTERVAL 1 DAY))
  UNION ALL
  SELECT
    TIMESTAMP_MICROS(event_timestamp) AS event_ts,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key='event_id') AS event_id,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key='uid') AS uid,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key='content_id') AS content_id,
    COALESCE(
      (SELECT value.string_value FROM UNNEST(event_params) WHERE key='content_index'),
      CAST((SELECT value.int_value FROM UNNEST(event_params) WHERE key='content_index') AS STRING)
    ) AS content_index,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key='scene') AS scene,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key='type') AS course_type,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key='result') AS result
  FROM `dino-english-497507.analytics_538991439.events_intraday_*`
  WHERE _TABLE_SUFFIX = FORMAT_DATE('%Y%m%d', @end_date)
), starts AS (
  SELECT * FROM base
  WHERE event_id='afterclass_practice_start' AND uid IS NOT NULL
), answers AS (
  SELECT * FROM base
  WHERE event_id='play_answer_submit' AND scene='words_pk'
    AND event_ts >= TIMESTAMP(@afterclass_start_date)
    AND uid IS NOT NULL AND content_id IS NOT NULL
), attributed AS (
  SELECT
    a.* EXCEPT(course_type),
    s.course_type,
    s.content_id AS class_id
  FROM answers a
  JOIN starts s
    ON s.uid=a.uid
   AND s.event_ts<=a.event_ts
   AND s.event_ts>=TIMESTAMP_SUB(a.event_ts, INTERVAL 7 DAY)
  QUALIFY ROW_NUMBER() OVER (
    PARTITION BY a.uid,a.event_ts,a.content_id,COALESCE(a.content_index,'')
    ORDER BY s.event_ts DESC
  )=1
), question_rollup AS (
  SELECT
    CASE
      WHEN UPPER(course_type)='TRIAL' THEN 'trial_after'
      WHEN UPPER(course_type) IN ('ONBOARDING','') OR course_type IS NULL THEN NULL
      ELSE 'formal_after'
    END AS scene,
    uid,
    class_id,
    COALESCE(content_index,'') AS content_index,
    MIN(IF(result='correct',event_ts,NULL)) AS first_correct_ts,
    ARRAY_AGG(STRUCT(event_ts,result) ORDER BY event_ts) AS submissions
  FROM attributed
  GROUP BY 1,2,3,4
), passed AS (
  SELECT
    CAST(DATE(first_correct_ts) AS STRING) AS answer_date,
    scene,
    uid,
    (SELECT COUNT(*) FROM UNNEST(submissions) s WHERE s.event_ts<=first_correct_ts) AS attempts
  FROM question_rollup
  WHERE scene IS NOT NULL AND first_correct_ts IS NOT NULL
)
SELECT
  answer_date,
  scene,
  COUNT(DISTINCT uid) AS users,
  COUNT(*) AS questions,
  SUM(attempts) AS attempts,
  COUNTIF(attempts=1) AS once,
  COUNTIF(attempts=2) AS twice,
  COUNTIF(attempts=3) AS three,
  COUNTIF(attempts>=4) AS four_plus,
  ROUND(AVG(attempts),4) AS avg_attempts,
  APPROX_QUANTILES(attempts,100)[OFFSET(50)] AS p50,
  APPROX_QUANTILES(attempts,100)[OFFSET(90)] AS p90
FROM passed
GROUP BY answer_date, scene
ORDER BY answer_date, scene;
