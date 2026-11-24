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
        JSON_VALUE(answer, '$.stepId') IN ('child_exact_age', 'child_age', 'self_age'),
        JSON_VALUE(answer, '$.optionId'),
        NULL
      ) IGNORE NULLS LIMIT 1
    )[SAFE_OFFSET(0)] AS age_option,
    ARRAY_AGG(
      IF(
        STARTS_WITH(IFNULL(JSON_VALUE(answer, '$.stepId'), ''), 'placement_'),
        JSON_VALUE(answer, '$.optionId'),
        NULL
      ) IGNORE NULLS LIMIT 1
    )[SAFE_OFFSET(0)] AS ability_option
  FROM placement
  LEFT JOIN UNNEST(IFNULL(JSON_QUERY_ARRAY(payload, '$.answers'), [])) AS answer
  GROUP BY class_id
),
age_event_base AS (
  SELECT
    CAST(COALESCE(uid, user_id) AS STRING) AS user_id,
    CAST(content_id AS STRING) AS content_id,
    COALESCE(
      TIMESTAMP_MILLIS(client_event_time_ms),
      TIMESTAMP_MICROS(event_timestamp)
    ) AS event_at
  FROM `dino-english-497507.de_dwd.dwd_firebase_event_di`
  WHERE DATE(stat_date) BETWEEN DATE '2026-07-01' AND @end_date
    AND event_id = 'step_submitted'
    AND (
      STARTS_WITH(IFNULL(CAST(content_id AS STRING), ''), '3_learner_age:')
      OR STARTS_WITH(IFNULL(CAST(content_id AS STRING), ''), 'learner_age:')
    )
),
age_events AS (
  SELECT
    s.class_id,
    ARRAY_AGG(a.content_id IGNORE NULLS ORDER BY a.event_at DESC LIMIT 1)[SAFE_OFFSET(0)] AS age_content
  FROM starts s
  LEFT JOIN age_event_base a
    ON a.user_id = s.user_id
   AND a.event_at <= s.start_at
  GROUP BY s.class_id
),
help_event_base AS (
  SELECT
    CAST(class_id AS STRING) AS class_id,
    CAST(event_id AS STRING) AS event_id,
    COALESCE(
      TIMESTAMP_MILLIS(client_event_time_ms),
      TIMESTAMP_MICROS(event_timestamp)
    ) AS event_at
  FROM `dino-english-497507.de_dwd.dwd_firebase_event_di`
  WHERE DATE(stat_date) BETWEEN @l56_start_date AND @end_date
    AND event_name = 'click'
    AND event_id IN (
      'class_help', 'class_help_next_page', 'class_help_dino', 'class_help_feedback'
    )
    AND SAFE_CAST(lesson_id AS INT64) IN (1613, 1614)
    AND class_id IS NOT NULL
),
help_events AS (
  SELECT
    h.class_id,
    CONCAT(
      'h:', COALESCE(STRING_AGG(IF(h.event_id = 'class_help', FORMAT_TIMESTAMP('%Y-%m-%dT%H:%M:%S', h.event_at, 'UTC'), NULL), '|' ORDER BY h.event_at), ''),
      ';n:', COALESCE(STRING_AGG(IF(h.event_id = 'class_help_next_page', FORMAT_TIMESTAMP('%Y-%m-%dT%H:%M:%S', h.event_at, 'UTC'), NULL), '|' ORDER BY h.event_at), ''),
      ';d:', COALESCE(STRING_AGG(IF(h.event_id = 'class_help_dino', FORMAT_TIMESTAMP('%Y-%m-%dT%H:%M:%S', h.event_at, 'UTC'), NULL), '|' ORDER BY h.event_at), ''),
      ';f:', COALESCE(STRING_AGG(IF(h.event_id = 'class_help_feedback', FORMAT_TIMESTAMP('%Y-%m-%dT%H:%M:%S', h.event_at, 'UTC'), NULL), '|' ORDER BY h.event_at), '')
    ) AS help_events
  FROM help_event_base h
  JOIN starts s USING (class_id)
  GROUP BY h.class_id
),
conversation_messages AS (
  SELECT
    CAST(m.class_id AS STRING) AS class_id,
    m.role,
    IFNULL(m.agent_role, '') AS agent_role,
    TRIM(COALESCE(m.raw_content, m.content, '')) AS text
  FROM `dino-english-497507.de_ods.llm_conversation_message` m
  JOIN starts s ON CAST(m.class_id AS STRING) = s.class_id
  QUALIFY ROW_NUMBER() OVER (PARTITION BY m.id ORDER BY m.update_time DESC) = 1
),
student_turns AS (
  SELECT
    class_id,
    COUNTIF(
      role = 'user'
      AND agent_role != 'ASSISTANT'
      AND NOT STARTS_WITH(text, '# Role')
      AND NOT STARTS_WITH(text, '# 角色')
      AND NOT STARTS_WITH(text, '# 模板')
      AND NOT STARTS_WITH(text, '<system_control')
      AND NOT STARTS_WITH(text, 'The student')
      AND NOT STARTS_WITH(text, 'The UI')
      AND TRIM(REGEXP_REPLACE(
        REGEXP_REPLACE(
          REGEXP_REPLACE(text, r'(?i)\s*<system_teaching_step_context>[\s\S]*$', ''),
          r'(?i)</?student_message>',
          ''
        ),
        r'(?i)\[(?:TEACHER|STUDENT|TEMPLATE|ANIMATION|AUDIO|VIDEO|BOARD|UI|WAIT|PAUSE|PLAY|STOP|SHOW|HIDE|POINT|WAVE|NOD|SMILE|CLAP|THUMBS|LOOK|LISTEN|SPEAK|REPEAT|READ|REWARD|DINO)[A-Z0-9_:-]*\]',
        ''
      )) != ''
    ) AS student_turns
  FROM conversation_messages
  GROUP BY class_id
),
device_raw AS (
  SELECT
    user_id,
    device.mobile_brand_name AS brand,
    device.mobile_model_name AS model,
    device.mobile_os_hardware_model AS hardware,
    TIMESTAMP_MICROS(event_timestamp) AS event_at
  FROM `dino-english-497507.analytics_538991439.events_*`
  WHERE REGEXP_CONTAINS(_TABLE_SUFFIX, r'^\d{8}$')
    AND _TABLE_SUFFIX BETWEEN FORMAT_DATE('%Y%m%d', @l56_start_date) AND FORMAT_DATE('%Y%m%d', @end_date)
    AND user_id IN (SELECT user_id FROM starts)
  UNION ALL
  SELECT
    user_id,
    device.mobile_brand_name AS brand,
    device.mobile_model_name AS model,
    device.mobile_os_hardware_model AS hardware,
    TIMESTAMP_MICROS(event_timestamp) AS event_at
  FROM `dino-english-497507.analytics_538991439.events_intraday_*`
  WHERE _TABLE_SUFFIX BETWEEN FORMAT_DATE('%Y%m%d', DATE_SUB(@end_date, INTERVAL 2 DAY)) AND FORMAT_DATE('%Y%m%d', @end_date)
    AND user_id IN (SELECT user_id FROM starts)
),
device_counts AS (
  SELECT
    user_id,
    COALESCE(NULLIF(hardware, ''), NULLIF(model, ''), NULLIF(brand, '')) AS device_model,
    COUNT(*) AS event_count,
    MAX(event_at) AS last_event_at
  FROM device_raw
  WHERE COALESCE(NULLIF(hardware, ''), NULLIF(model, ''), NULLIF(brand, '')) IS NOT NULL
  GROUP BY user_id, device_model
),
device_by_user AS (
  SELECT
    user_id,
    ARRAY_AGG(device_model ORDER BY event_count DESC, last_event_at DESC LIMIT 1)[SAFE_OFFSET(0)] AS device_model
  FROM device_counts
  GROUP BY user_id
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
    WHEN COALESCE(a.age_option, REGEXP_EXTRACT(g.age_content, r'(age_[A-Za-z0-9_]+)')) = 'age_3_5' THEN '3–5'
    WHEN COALESCE(a.age_option, REGEXP_EXTRACT(g.age_content, r'(age_[A-Za-z0-9_]+)')) = 'age_6_8' THEN '6–8'
    WHEN COALESCE(a.age_option, REGEXP_EXTRACT(g.age_content, r'(age_[A-Za-z0-9_]+)')) = 'age_9_12' THEN '9–12'
    WHEN COALESCE(a.age_option, REGEXP_EXTRACT(g.age_content, r'(age_[A-Za-z0-9_]+)')) = 'age_13_17' THEN '13–17'
    WHEN COALESCE(a.age_option, REGEXP_EXTRACT(g.age_content, r'(age_[A-Za-z0-9_]+)')) = 'age_13_plus' THEN '13+'
    WHEN COALESCE(a.age_option, REGEXP_EXTRACT(g.age_content, r'(age_[A-Za-z0-9_]+)')) = 'age_18_plus' THEN '18+'
    WHEN REGEXP_CONTAINS(COALESCE(a.age_option, REGEXP_EXTRACT(g.age_content, r'(age_[A-Za-z0-9_]+)'), ''), r'^age_([3-9]|1[0-2])$')
      THEN REGEXP_EXTRACT(COALESCE(a.age_option, REGEXP_EXTRACT(g.age_content, r'(age_[A-Za-z0-9_]+)')), r'^age_(\d+)$')
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
    WHEN REGEXP_CONTAINS(COALESCE(a.age_option, REGEXP_EXTRACT(g.age_content, r'(age_[A-Za-z0-9_]+)'), ''), r'^age_([3-9]|1[0-2])$')
      THEN REGEXP_EXTRACT(COALESCE(a.age_option, REGEXP_EXTRACT(g.age_content, r'(age_[A-Za-z0-9_]+)')), r'^age_(\d+)$')
    ELSE ''
  END AS age_year,
  COALESCE(t.template_starts, '') AS template_starts,
  COALESCE(c.device_os, '') AS os,
  COALESCE(u.student_turns, 0) AS student_turns,
  COALESCE(h.help_events, '') AS help_events,
  COALESCE(d.device_model, '') AS device_model
FROM class_events c
LEFT JOIN `dino-english-497507.de_ods.student_class` sc
  ON CAST(sc.id AS STRING) = c.class_id
 AND SAFE_CAST(sc.lesson_id AS INT64) = CASE c.level WHEN 5 THEN 1613 WHEN 6 THEN 1614 END
LEFT JOIN latest_profiles p USING (user_id)
LEFT JOIN profile_answers a USING (class_id)
LEFT JOIN age_events g USING (class_id)
LEFT JOIN stage_counts k USING (level, class_id)
LEFT JOIN stage_timeline t USING (level, class_id)
LEFT JOIN student_turns u USING (class_id)
LEFT JOIN help_events h USING (class_id)
LEFT JOIN device_by_user d USING (user_id)
WHERE COALESCE(p.user_type, '') != 'test'
ORDER BY c.start_at, c.level;
