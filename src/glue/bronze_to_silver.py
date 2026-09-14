import sys
from awsglue.transforms import *
from awsglue.utils import getResolvedOptions
from pyspark.context import SparkContext
from awsglue.context import GlueContext
from awsglue.job import Job
from pyspark.sql import functions as F
from pyspark.sql.types import *
from datetime import datetime, timedelta
from pyspark.sql.window import Window

# --- Args --------------------------------------------------------------
args = getResolvedOptions(sys.argv, [
    'JOB_NAME',
    'bucket',
    'processing_date',   # 'YYYY-MM-DD' for a single day OR 'all' for full reload
])

sc = SparkContext()
glueContext = GlueContext(sc)
spark = glueContext.spark_session
job = Job(glueContext)
job.init(args['JOB_NAME'], args)

# Dynamic partition overwrite — only rewrites the date partitions in the dataframe
spark.conf.set("spark.sql.sources.partitionOverwriteMode", "dynamic")

bucket = args['bucket']
processing_date = args['processing_date']
target_path = f"s3://{bucket}/silver/weather/"

# --- Decide the source path based on the mode -------------------------
if processing_date.lower() == 'all':
    # Full reload — read the entire Bronze layer
    source_path = f"s3://{bucket}/bronze/weather/*/*/*/*/*/data.json"
    print(f"🔄 FULL RELOAD mode — reading all Bronze data")
else:
    # Single-day mode — read just that day
    year, month, day = processing_date.split('-')
    source_path = (
        f"s3://{bucket}/bronze/weather/"
        f"year={year}/month={month}/day={day}/*/*/data.json"
    )
    print(f"📅 SINGLE-DAY mode — processing {processing_date}")

print(f"Source: {source_path}")

# --- Read Bronze JSON --------------------------------------------------
df = (spark.read
    .option("multiline", True)
    .json(source_path))

raw_count = df.count()
print(f"Read {raw_count} raw records")

if raw_count == 0:
    print("⚠️ No Bronze data found. Exiting.")
    job.commit()
    sys.exit(0)

df.printSchema()

# --- Flatten and clean -------------------------------------------------
silver = (df
    .select(
        F.col("_source_city").alias("city"),
        F.col("_source_country").alias("country"),
        F.col("_ingestion_timestamp").cast(TimestampType()).alias("ingestion_ts"),
        F.from_unixtime(F.col("dt")).cast(TimestampType()).alias("measurement_ts"),
        F.col("main.temp").cast(DoubleType()).alias("temperature_celsius"),
        F.col("main.feels_like").cast(DoubleType()).alias("feels_like_celsius"),
        F.col("main.humidity").cast(IntegerType()).alias("humidity_pct"),
        F.col("main.pressure").cast(IntegerType()).alias("pressure_hpa"),
        F.col("wind.speed").cast(DoubleType()).alias("wind_speed_ms"),
        F.col("wind.deg").cast(IntegerType()).alias("wind_direction_deg"),
        F.col("clouds.all").cast(IntegerType()).alias("cloudiness_pct"),
        F.col("weather")[0]["main"].alias("weather_condition"),
        F.col("weather")[0]["description"].alias("weather_description"),
        F.col("coord.lat").cast(DoubleType()).alias("latitude"),
        F.col("coord.lon").cast(DoubleType()).alias("longitude"),
    )
    .filter(F.col("temperature_celsius").between(-50, 60))
    .filter(F.col("humidity_pct").between(0, 100))
    .filter(F.col("city").isNotNull())
    .withColumn("date", F.to_date(F.col("measurement_ts")))
    .withColumn("hour", F.hour(F.col("measurement_ts")))
    .withColumn("rn",
        F.row_number().over(
            Window
            .partitionBy("city", "date", "hour")
            .orderBy(F.desc("ingestion_ts"))
        )
    )
    .filter(F.col("rn") == 1)
    .drop("rn", "hour")
    .withColumn("updated_at", F.current_timestamp())
)

# --- Filter to processing scope ---------------------------------------
if processing_date.lower() == 'all':
    silver_filtered = silver
    distinct_dates = [row['date'] for row in silver.select("date").distinct().collect()]
    print(f"Full reload will overwrite {len(distinct_dates)} date partitions: {distinct_dates}")
else:
    silver_filtered = silver.filter(F.col("date") == processing_date)

final_count = silver_filtered.count()
print(f"After cleaning and dedup: {final_count} records to write")

# --- Write Parquet with dynamic partition overwrite -------------------
# Scale the number of output files based on data volume
output_partitions = max(1, final_count // 500_000)

(silver_filtered
    .repartition(output_partitions, "date")
    .write
    .mode("overwrite")
    .partitionBy("date")
    .parquet(target_path))

if processing_date.lower() == 'all':
    print(f"✅ Full reload completed — Silver rewritten for all dates")
else:
    print(f"✅ Silver layer updated at {target_path}date={processing_date}/")

job.commit()