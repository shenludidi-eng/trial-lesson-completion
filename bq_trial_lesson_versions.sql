-- Trial-lesson production version mapping for L1-L4.
--
-- Structural V1 / V2 still comes from the first template in the class table.
-- This mapping adds student_class.lesson_version so experiments that reuse an
-- existing structure (notably L2 V3 / V4 Talker) can be split correctly.
WITH stage_starts AS (
  SELECT
    CASE SAFE_CAST(lesson_id AS INT64)
      WHEN 732 THEN 1
      WHEN 1615 THEN 2
      WHEN 734 THEN 3
      WHEN 733 THEN 4
    END AS level,
    SAFE_CAST(lesson_id AS INT64) AS lesson_id,
    CAST(class_id AS STRING) AS class_id,
    CAST(uid AS STRING) AS user_id,
    COALESCE(
      TIMESTAMP_MILLIS(client_event_time_ms),
      TIMESTAMP_MICROS(event_timestamp)
    ) AS event_at
  FROM `dino-english-497507.de_dwd.dwd_firebase_event_di`
  WHERE DATE(stat_date) BETWEEN DATE '2026-07-01' AND @end_date
    AND event_name = 'trigger'
    AND event_id = 'class_stage_start'
    AND SAFE_CAST(lesson_id AS INT64) IN (732, 1615, 734, 733)
    AND class_id IS NOT NULL
    AND uid IS NOT NULL
),
class_keys AS (
  SELECT
    level,
    lesson_id,
    class_id,
    ARRAY_AGG(user_id ORDER BY event_at, user_id LIMIT 1)[OFFSET(0)] AS user_id,
    MIN(event_at) AS first_start_at
  FROM stage_starts
  GROUP BY level, lesson_id, class_id
  HAVING MIN(event_at) >= TIMESTAMP '2026-08-01 00:00:00+00'
)
SELECT
  FORMAT_DATE('%F', DATE(k.first_start_at)) AS start_date,
  k.level,
  k.class_id,
  LOWER(SUBSTR(TO_HEX(SHA256(k.user_id)), 1, 12)) AS user_key,
  FORMAT_TIMESTAMP('%Y-%m-%dT%H:%M:%S', k.first_start_at, 'UTC') AS start,
  COALESCE(CAST(sc.lesson_version AS STRING), '') AS lesson_version
FROM class_keys k
LEFT JOIN `dino-english-497507.de_ods.student_class` sc
  ON CAST(sc.id AS STRING) = k.class_id
 AND SAFE_CAST(sc.lesson_id AS INT64) = k.lesson_id
ORDER BY level, start, class_id;
