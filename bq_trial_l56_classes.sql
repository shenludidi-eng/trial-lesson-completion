-- Production L5 / L6 trial-lesson rows for the public completion dashboard.
--
-- L5 (1613) and L6 (1614) had internal traffic before launch.  The public
-- cohort starts on @l56_start_date so pre-launch QA never pollutes production
-- completion or funnel metrics.
WITH event_base AS (
  SELECT
    CASE SAFE_CAST(lesson_id AS INT64)
      WHEN 1613 THEN 5
      WHEN 1614 THEN 6
    END AS level,
    CAST(class_id AS STRING) AS class_id,
    CAST(uid AS STRING) AS user_id,
    event_id,
    CAST(type AS STRING) AS event_type,
    CAST(result AS STRING) AS event_result,
    SPLIT(CAST(template_id AS STRING), '#')[SAFE_OFFSET(0)] AS template_id,
    COALESCE(country, install_country) AS country,
    CAST(device_os AS STRING) AS device_os,
    COALESCE(
      TIMESTAMP_MILLIS(client_event_time_ms),
      TIMESTAMP_MICROS(event_timestamp)
    ) AS event_at
  FROM `dino-english-497507.de_dwd.dwd_firebase_event_di`
  WHERE DATE(stat_date) BETWEEN @l56_start_date AND @end_date
    AND event_name = 'trigger'
    AND SAFE_CAST(lesson_id AS INT64) IN (1613, 1614)
    AND class_id IS NOT NULL
    AND uid IS NOT NULL
),
starts AS (
  SELECT
    level,
    class_id,
    ARRAY_AGG(user_id ORDER BY event_at, user_id LIMIT 1)[OFFSET(0)] AS user_id,
    ARRAY_AGG(template_id ORDER BY event_at, template_id LIMIT 1)[OFFSET(0)] AS first_template_id,
    MIN(event_at) AS start_at
  FROM event_base
  WHERE event_id = 'class_stage_start'
  GROUP BY level, class_id
  HAVING MIN(event_at) >= TIMESTAMP(@l56_start_date)
),
latest_profiles AS (
  SELECT
    CAST(user_id AS STRING) AS user_id,
    LOWER(CAST(user_type AS STRING)) AS user_type
  FROM `dino-english-497507.de_ods.user_profile`
  QUALIFY ROW_NUMBER() OVER (
    PARTITION BY CAST(user_id AS STRING)
    ORDER BY updated_at DESC
  ) = 1
),
placement AS (
  SELECT
    s.class_id,
    CAST(p.payload_snapshot AS STRING) AS payload
  FROM starts s
  LEFT JOIN `dino-english-497507.de_ods.class_user_placement_log` p
    ON CAST(p.user_id AS STRING) = s.user_id
   AND p.source = 'ONBOARDING'
   AND p.create_time <= s.start_at
  QUALIFY ROW_NUMBER() OVER (
    PARTITION BY s.class_id
    ORDER BY p.create_time DESC
  ) = 1
),
profile_answers AS (
  SELECT
    class_id,
    ARRAY_AGG(
      IF(
        JSON_VALUE(answer, '$.stepId') IN ('child_age', 'self_age'),
        JSON_VALUE(answer, '$.optionId'),
        NULL
      ) IGNORE NULLS LIMIT 1
    )[SAFE_OFFSET(0)] AS age_option,
    ARRAY_AGG(
      IF(
        STARTS_WITH(IFNULL(JSON_VALUE(answer, '$.stepId'), ''), 'placement_age_'),
        JSON_VALUE(answer, '$.optionId'),
        NULL
      ) IGNORE NULLS LIMIT 1
    )[SAFE_OFFSET(0)] AS ability_option
  FROM placement
  LEFT JOIN UNNEST(IFNULL(JSON_QUERY_ARRAY(payload, '$.answers'), [])) AS answer
  GROUP BY class_id
),
stage_events AS (
  SELECT
    e.level,
    e.class_id,
    e.event_at,
    CASE e.template_id
      WHEN 'warm-up-template_l5l6' THEN 'wu56'
      WHEN 'reward-chest-intro' THEN 'ri'
      WHEN 'lead-in-template_l5l6' THEN 'li56'
      WHEN 'play-video-template' THEN 'pv'
      WHEN 'word_teach_image_l5l6' THEN 'wt56'
      WHEN 'practice_listen_choose_image' THEN 'lci'
      WHEN 'word_practice_word_select_img' THEN 'wsi'
      WHEN 'word_practice_img_select_word' THEN 'isw'
      WHEN 'word_practice_oral_assessment' THEN 'woa'
      WHEN 'word_practice_spelling_l2l6' THEN 'spl'
      WHEN 'reward-chest-step1-template' THEN 'rc1'
      WHEN 'sentence_teach_explain_trail_l1' THEN 'ste'
      WHEN 'sentence_practice_oral_assessment' THEN 'soa'
      WHEN 'sentence_word_order' THEN 'swo'
      WHEN 'reward-chest-step2-template' THEN 'rc2'
      WHEN 'wrapup_summary_video_trail' THEN 'wp'
      WHEN 'free_talk_images' THEN 'fti'
      WHEN 'decodable_reader_images' THEN 'dri'
      WHEN 'discourse_practice_reading_question' THEN 'dpq'
      WHEN 'photo_time_l3l6' THEN 'ph36'
      WHEN 'reward-chest-step3-template' THEN 'rc3'
    END AS code
  FROM event_base e
  JOIN starts s USING (level, class_id)
  WHERE e.event_id = 'class_stage_start'
),
stage_counts AS (
  SELECT
    level,
    class_id,
    STRING_AGG(FORMAT('%s:%d', code, count), ';' ORDER BY first_at, code) AS templates
  FROM (
    SELECT
      level,
      class_id,
      code,
      COUNT(*) AS count,
      MIN(event_at) AS first_at
    FROM stage_events
    WHERE code IS NOT NULL
    GROUP BY level, class_id, code
  )
  GROUP BY level, class_id
),
stage_timeline AS (
  SELECT
    e.level,
    e.class_id,
    STRING_AGG(
      FORMAT('%s:%d', e.code, TIMESTAMP_DIFF(e.event_at, s.start_at, SECOND)),
      '|' ORDER BY e.event_at, e.code
    ) AS template_starts,
    MIN(IF(e.code = 'wp', e.event_at, NULL)) AS wrapup_at
  FROM stage_events e
  JOIN starts s USING (level, class_id)
  WHERE e.code IS NOT NULL
  GROUP BY e.level, e.class_id
),
class_events AS (
  SELECT
    s.level,
    s.class_id,
    s.user_id,
    s.first_template_id,
    s.start_at,
    MIN(IF(e.event_type = 'trial' AND e.event_result = 'complete', e.event_at, NULL)) AS complete_at,
    ARRAY_AGG(e.country IGNORE NULLS ORDER BY e.event_at LIMIT 1)[SAFE_OFFSET(0)] AS country,
    ARRAY_AGG(e.device_os IGNORE NULLS ORDER BY e.event_at LIMIT 1)[SAFE_OFFSET(0)] AS device_os,
    STRING_AGG(
      IF(e.event_id = 'class_stage_start', FORMAT_TIMESTAMP('%Y-%m-%dT%H:%M:%S', e.event_at, 'UTC'), NULL),
      '|' ORDER BY e.event_at
    ) AS starts
  FROM starts s
  JOIN event_base e USING (level, class_id)
  GROUP BY s.level, s.class_id, s.user_id, s.first_template_id, s.start_at
)
SELECT
  FORMAT_DATE('%F', DATE(c.start_at)) AS start_date,
  c.level,
  FORMAT_TIMESTAMP('%Y-%m-%dT%H:%M:%S', c.start_at, 'UTC') AS start,
  IF(c.complete_at IS NULL, '', FORMAT_TIMESTAMP('%Y-%m-%dT%H:%M:%S', c.complete_at, 'UTC')) AS complete,
  COALESCE(c.country, '') AS country,
  CASE
    WHEN a.age_option = 'age_3_5' THEN '3–5'
    WHEN a.age_option = 'age_6_8' THEN '6–8'
    WHEN a.age_option = 'age_9_12' THEN '9–12'
    WHEN a.age_option = 'age_13_17' THEN '13–17'
    WHEN a.age_option = 'age_13_plus' THEN '13+'
    WHEN a.age_option = 'age_18_plus' THEN '18+'
    WHEN REGEXP_CONTAINS(IFNULL(a.age_option, ''), r'^age_([3-9]|1[0-2])$')
      THEN REGEXP_EXTRACT(a.age_option, r'^age_(\d+)$')
    ELSE ''
  END AS age,
  CASE
    WHEN ENDS_WITH(IFNULL(a.ability_option, ''), '_just_starting') THEN 'JS'
    WHEN ENDS_WITH(IFNULL(a.ability_option, ''), '_new_to_english') THEN 'NE'
    WHEN ENDS_WITH(IFNULL(a.ability_option, ''), '_knows_a_little') THEN 'KL'
    WHEN ENDS_WITH(IFNULL(a.ability_option, ''), '_knows_basics') THEN 'KB'
    WHEN ENDS_WITH(IFNULL(a.ability_option, ''), '_basic_level') THEN 'BL'
    WHEN ENDS_WITH(IFNULL(a.ability_option, ''), '_simple_conversations') THEN 'SC'
    WHEN ENDS_WITH(IFNULL(a.ability_option, ''), '_can_read_write') THEN 'RW'
    WHEN ENDS_WITH(IFNULL(a.ability_option, ''), '_can_read_talk') THEN 'RT'
    WHEN ENDS_WITH(IFNULL(a.ability_option, ''), '_can_communicate') THEN 'CC'
    WHEN ENDS_WITH(IFNULL(a.ability_option, ''), '_more_advanced') THEN 'MA'
    WHEN ENDS_WITH(IFNULL(a.ability_option, ''), '_advanced') THEN 'AD'
    WHEN ENDS_WITH(IFNULL(a.ability_option, ''), '_not_sure') THEN 'NS'
    ELSE ''
  END AS ability,
  CASE
    WHEN SAFE_CAST(sc.lesson_version AS INT64) IN (1, 2)
      THEN CAST(SAFE_CAST(sc.lesson_version AS INT64) AS STRING)
    -- Some newly-created classes can emit Firebase events before the
    -- student_class snapshot has lesson_version.  V1 starts with warm-up;
    -- V2 starts directly with lead-in (L5) or free-talk (L6).
    WHEN c.first_template_id = 'warm-up-template_l5l6' THEN '1'
    ELSE '2'
  END AS version,
  c.starts,
  IF(t.wrapup_at IS NULL, '', FORMAT_TIMESTAMP('%Y-%m-%dT%H:%M:%S', t.wrapup_at, 'UTC')) AS wrapup,
  '' AS tier,
  LOWER(SUBSTR(TO_HEX(SHA256(c.user_id)), 1, 12)) AS user_key,
  COALESCE(k.templates, '') AS templates,
  CASE
    WHEN REGEXP_CONTAINS(IFNULL(a.age_option, ''), r'^age_([3-9]|1[0-2])$')
      THEN REGEXP_EXTRACT(a.age_option, r'^age_(\d+)$')
    ELSE ''
  END AS age_year,
  COALESCE(t.template_starts, '') AS template_starts,
  COALESCE(c.device_os, '') AS os
FROM class_events c
LEFT JOIN `dino-english-497507.de_ods.student_class` sc
  ON CAST(sc.id AS STRING) = c.class_id
 AND SAFE_CAST(sc.lesson_id AS INT64) = CASE c.level WHEN 5 THEN 1613 WHEN 6 THEN 1614 END
LEFT JOIN latest_profiles p USING (user_id)
LEFT JOIN profile_answers a USING (class_id)
LEFT JOIN stage_counts k USING (level, class_id)
LEFT JOIN stage_timeline t USING (level, class_id)
WHERE COALESCE(p.user_type, '') != 'test'
ORDER BY c.start_at, c.level;
