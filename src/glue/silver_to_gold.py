import sys
from awsglue.transforms import *
from awsglue.utils import getResolvedOptions
from pyspark.context import SparkContext
from awsglue.context import GlueContext
from awsglue.job import Job
from pyspark.sql import functions as F
from pyspark.sql.window import Window

args = getResolvedOptions(sys.argv, [
    'JOB_NAME', 'bucket', 'processing_date',
])

sc = SparkContext()
glueContext = GlueContext(sc)
spark = glueContext.spark_session
job = Job(glueContext)
job.init(args['JOB_NAME'], args)

# Dynamic partition overwrite - only rewrites the dates being processed
spark.conf.set("spark.sql.sources.partitionOverwriteMode", "dynamic")

bucket = args['bucket']
processing_date = args['processing_date']

source_path = f"s3://{bucket}/silver/weather/"
gold_base = f"s3://{bucket}/gold/"

# Read Silver
silver_full = spark.read.parquet(source_path)

# Filter based on mode
if processing_date.lower() == 'all':
    print("FULL RELOAD mode - reading all Silver data")
    silver = silver_full
    distinct_dates = sorted([row['date'] for row in silver.select("date").distinct().collect()])
    print(f"Processing {len(distinct_dates)} distinct dates")
    if distinct_dates:
        print(f"Date range: {distinct_dates[0]} to {distinct_dates[-1]}")
    dates_to_write = distinct_dates
else:
    print(f"SINGLE-DAY mode - processing {processing_date}")
    silver = silver_full.filter(
        F.col("date").between(
            F.date_sub(F.lit(processing_date), 6),
            F.lit(processing_date)
        )
    )
    dates_to_write = [processing_date]

silver_count = silver.count()
print(f"Silver rows in scope: {silver_count}")

if silver_count == 0:
    print("No Silver data to process. Exiting.")
    job.commit()
    sys.exit(0)

# GOLD 1 - Daily stats per city
if processing_date.lower() == 'all':
    daily_source = silver
else:
    daily_source = silver.filter(F.col("date") == processing_date)

daily_stats = (daily_source
    .groupBy("date", "city", "country")
    .agg(
        F.avg("temperature_celsius").alias("avg_temp"),
        F.min("temperature_celsius").alias("min_temp"),
        F.max("temperature_celsius").alias("max_temp"),
        F.avg("humidity_pct").alias("avg_humidity"),
        F.avg("wind_speed_ms").alias("avg_wind_speed"),
        F.max("wind_speed_ms").alias("max_wind_speed"),
        F.count("*").alias("measurement_count"),
        F.first("weather_condition").alias("dominant_condition"),
    )
    .withColumn("temp_range", F.round(F.col("max_temp") - F.col("min_temp"), 2))
    .withColumn("updated_at", F.current_timestamp())
)

daily_count = daily_stats.count()
print(f"Gold 1 (city_daily_stats): {daily_count} rows to write")

(daily_stats
    .repartition(1, "date")
    .write
    .mode("overwrite")
    .partitionBy("date")
    .parquet(f"{gold_base}city_daily_stats/"))

print("Gold: city_daily_stats written")

# GOLD 2 - Weather alerts
alerts = (daily_source
    .select(
        F.col("date"),
        F.col("city"),
        F.col("measurement_ts"),
        F.col("temperature_celsius"),
        F.col("wind_speed_ms"),
        F.col("weather_condition"),
        F.when(F.col("temperature_celsius") > 35, F.lit("EXTREME_HEAT"))
         .when(F.col("temperature_celsius") < -10, F.lit("EXTREME_COLD"))
         .when(F.col("wind_speed_ms") > 20, F.lit("HIGH_WIND"))
         .when(F.col("weather_condition").isin("Thunderstorm", "Tornado"), F.lit("STORM"))
         .otherwise(F.lit(None))
         .alias("alert_type")
    )
    .filter(F.col("alert_type").isNotNull())
    .withColumn("updated_at", F.current_timestamp())
)

alerts_count = alerts.count()
print(f"Gold 2 (weather_alerts_summary): {alerts_count} rows to write")

if alerts_count > 0:
    (alerts
        .repartition(1, "date")
        .write
        .mode("overwrite")
        .partitionBy("date")
        .parquet(f"{gold_base}weather_alerts_summary/"))
    print("Gold: weather_alerts_summary written")
else:
    print("No alerts detected in scope - skipping write")

# GOLD 3 - Weekly rolling temperature trends
weekly_trends = (silver
    .groupBy("city", "date")
    .agg(F.avg("temperature_celsius").alias("daily_avg_temp"))
    .withColumn("week_avg_temp",
        F.avg("daily_avg_temp").over(
            Window.partitionBy("city")
                  .orderBy("date")
                  .rowsBetween(-6, 0)
        ))
    .withColumn("temp_trend",
        F.when(F.col("daily_avg_temp") > F.col("week_avg_temp") + 3, "WARMING")
         .when(F.col("daily_avg_temp") < F.col("week_avg_temp") - 3, "COOLING")
         .otherwise("STABLE"))
    .withColumn("updated_at", F.current_timestamp())
)

if processing_date.lower() != 'all':
    weekly_trends = weekly_trends.filter(F.col("date") == processing_date)

trends_count = weekly_trends.count()
print(f"Gold 3 (temperature_trends_weekly): {trends_count} rows to write")

(weekly_trends
    .repartition(1, "date")
    .write
    .mode("overwrite")
    .partitionBy("date")
    .parquet(f"{gold_base}temperature_trends_weekly/"))

print("Gold: temperature_trends_weekly written")

if processing_date.lower() == 'all':
    print("Full reload of Gold completed - all dates written")
else:
    print(f"Gold updated for {processing_date}")

job.commit()