-- Production query: daily exercise performance by UTC date and user dimensions.
-- Profile rule: use the latest applied onboarding placement at or before the answer;
-- current user_profile.age_range is only an age fallback. Ability stays unknown if
-- no historical placement is available.
WITH answers AS (
  SELECT
    event_uuid,
    CAST(user_id AS STRING) AS user_id,
    CAST(stat_date AS STRING) AS answer_date,
    event_timestamp,
    CASE WHEN type = 'trial' THEN 'trial_in' ELSE 'formal_in' END AS scene,
    SAFE_CAST(REGEXP_EXTRACT(level_id, r'(\d+)') AS INT64) AS level,
    template_id AS question_type,
    GREATEST(1, COALESCE(SAFE_CAST(`count` AS INT64), 1)) AS pass_attempts
  FROM `dino-english-497507.de_dwd.dwd_firebase_event_di`
  WHERE DATE(stat_date) BETWEEN @start_date AND @end_date
    AND event_id = 'class_answer_submit'
    AND user_id IS NOT NULL
    AND template_id IS NOT NULL
    AND SAFE_CAST(REGEXP_EXTRACT(level_id, r'(\d+)') AS INT64) BETWEEN 1 AND 6
    AND (type = 'trial' OR COALESCE(type, '') NOT IN ('', 'trial', 'onboarding'))
),
placements AS (
  SELECT
    CAST(user_id AS STRING) AS user_id,
    event_timestamp,
    CASE
      WHEN REGEXP_CONTAINS(content_id, r'^placement_3_5_') THEN '3–5'
      WHEN REGEXP_CONTAINS(content_id, r'^placement_6_8_') THEN '6–8'
      WHEN REGEXP_CONTAINS(content_id, r'^placement_9_12_') THEN '9–12'
      WHEN REGEXP_CONTAINS(content_id, r'^placement_13_plus_') THEN '13+'
      ELSE NULL
    END AS age_band,
    CASE REGEXP_REPLACE(content_id, r'^placement_(3_5|6_8|9_12|13_plus)_', '')
      WHEN 'just_starting' THEN 'JS'
      WHEN 'new_to_english' THEN 'NE'
      WHEN 'knows_a_little' THEN 'KL'
      WHEN 'knows_the_basics' THEN 'KB'
      WHEN 'basic_level' THEN 'BL'
      WHEN 'simple_conversations' THEN 'SC'
      WHEN 'can_speak_up' THEN 'SU'
      WHEN 'can_read_write' THEN 'RW'
      WHEN 'can_read_talk' THEN 'RT'
      WHEN 'can_communicate' THEN 'CC'
      WHEN 'advanced' THEN 'AD'
      WHEN 'not_sure' THEN 'NS'
      ELSE 'UNKNOWN'
    END AS ability_code
  FROM `dino-english-497507.de_dwd.dwd_firebase_event_di`
  WHERE DATE(stat_date) BETWEEN @placement_start_date AND @end_date
    AND event_id = 'onboarding_option_click'
    AND REGEXP_CONTAINS(content_id, r'^placement_(3_5|6_8|9_12|13_plus)_')
    AND user_id IS NOT NULL
),
current_profile AS (
  SELECT
    CAST(user_id AS STRING) AS user_id,
    CASE
      WHEN REGEXP_CONTAINS(LOWER(age_range), r'(^|[^0-9])3[^0-9]+5') THEN '3–5'
      WHEN REGEXP_CONTAINS(LOWER(age_range), r'(^|[^0-9])6[^0-9]+8') THEN '6–8'
      WHEN REGEXP_CONTAINS(LOWER(age_range), r'(^|[^0-9])9[^0-9]+12') THEN '9–12'
      WHEN REGEXP_CONTAINS(LOWER(age_range), r'13|18|adult') THEN '13+'
      ELSE 'UNKNOWN'
    END AS current_age_band
  FROM `dino-english-497507.de_ods.user_profile`
  WHERE user_id IS NOT NULL
  QUALIFY ROW_NUMBER() OVER (
    PARTITION BY CAST(user_id AS STRING)
    ORDER BY updated_at DESC
  ) = 1
),
answers_with_profile AS (
  SELECT
    a.*,
    ARRAY_AGG(
      IF(
        p.event_timestamp <= a.event_timestamp,
        STRUCT(p.event_timestamp AS placement_ts, p.age_band, p.ability_code),
        NULL
      ) IGNORE NULLS
      ORDER BY p.event_timestamp DESC
      LIMIT 1
    )[SAFE_OFFSET(0)] AS placement
  FROM answers a
  LEFT JOIN placements p USING (user_id)
  GROUP BY
    a.event_uuid, a.user_id, a.answer_date, a.event_timestamp, a.scene,
    a.level, a.question_type, a.pass_attempts
),
enriched AS (
  SELECT
    a.scene,
    a.answer_date,
    a.level,
    a.question_type,
    COALESCE(a.placement.age_band, cp.current_age_band, 'UNKNOWN') AS age_band,
    COALESCE(a.placement.ability_code, 'UNKNOWN') AS ability_code,
    a.user_id,
    a.pass_attempts
  FROM answers_with_profile a
  LEFT JOIN current_profile cp USING (user_id)
)
SELECT
  answer_date,
  scene,
  level,
  question_type,
  age_band,
  ability_code,
  COUNT(DISTINCT user_id) AS users,
  COUNT(*) AS questions,
  SUM(pass_attempts) AS attempts,
  COUNTIF(pass_attempts = 1) AS once,
  COUNTIF(pass_attempts = 2) AS twice,
  COUNTIF(pass_attempts = 3) AS three,
  COUNTIF(pass_attempts >= 4) AS four_plus,
  ROUND(AVG(pass_attempts), 4) AS avg_attempts,
  APPROX_QUANTILES(pass_attempts, 100)[OFFSET(50)] AS p50,
  APPROX_QUANTILES(pass_attempts, 100)[OFFSET(90)] AS p90
FROM enriched
GROUP BY answer_date, scene, level, question_type, age_band, ability_code
ORDER BY answer_date, scene, level, question_type, age_band, ability_code;
