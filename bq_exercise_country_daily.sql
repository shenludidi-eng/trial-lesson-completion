-- Production query: daily in-class exercise performance by country and Level.
SELECT
  CAST(stat_date AS STRING) AS answer_date,
  CASE WHEN type='trial' THEN 'trial_in' ELSE 'formal_in' END AS scene,
  SAFE_CAST(REGEXP_EXTRACT(level_id, r'(\d+)') AS INT64) AS level,
  COALESCE(NULLIF(country,''),NULLIF(install_country,''),NULLIF(current_country,''),'(unknown)') AS country,
  COUNT(DISTINCT CAST(user_id AS STRING)) AS users,
  COUNT(*) AS questions,
  SUM(GREATEST(1,COALESCE(SAFE_CAST(`count` AS INT64),1))) AS attempts,
  COUNTIF(GREATEST(1,COALESCE(SAFE_CAST(`count` AS INT64),1))=1) AS once,
  COUNTIF(GREATEST(1,COALESCE(SAFE_CAST(`count` AS INT64),1))=2) AS twice,
  COUNTIF(GREATEST(1,COALESCE(SAFE_CAST(`count` AS INT64),1))=3) AS three,
  COUNTIF(GREATEST(1,COALESCE(SAFE_CAST(`count` AS INT64),1))>=4) AS four_plus
FROM `dino-english-497507.de_dwd.dwd_firebase_event_di`
WHERE DATE(stat_date) BETWEEN @start_date AND @end_date
  AND event_id='class_answer_submit'
  AND user_id IS NOT NULL
  AND SAFE_CAST(REGEXP_EXTRACT(level_id, r'(\d+)') AS INT64) BETWEEN 1 AND 6
  AND (type='trial' OR COALESCE(type,'') NOT IN ('','trial','onboarding'))
GROUP BY answer_date,scene,level,country
ORDER BY answer_date,scene,level,country;
