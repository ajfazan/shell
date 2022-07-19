##!/bin/sh

fix_rgb_background() {

  DIR=$(dirname $(realpath ${1}))

  generate_raster_footprint --remove-holes ${1} ${DIR}

  FOOTPRINT="${DIR}/$(basename ${1} | sed -r 's/^(.+)\.(.+)$/\1/').gpkg" 

  BBOX=$(mktemp -q --tmpdir=${TMPDIR} --suffix=".gpkg" XXXXXXXXXXXXXXXX)

  gdaltinex -q -f GPKG -lyr_name bbox ${BBOX} ${1}

  SQL="MBRMinX( geom ) AS x1, MBRMinY( geom ) AS y1, MBRMaxX( geom ) AS x2, MBRMaxY( geom ) AS y2"
  SQL="SELECT ${SQL} FROM bbox"

  CSV=$(mktemp -q --tmpdir=${TMPDIR} --suffix=".csv" XXXXXXXXXXXXXXXX)

  ogr2ogr -f CSV -sql "${SQL}" ${CSV} ${BBOX}

  sed -i '1d ; s/,/ /g' ${CSV}

  R_BAND=$(mktemp -q --tmpdir=${TMPDIR} --suffix=".tif" XXXXXXXXXXXXXXXX)
  G_BAND=$(mktemp -q --tmpdir=${TMPDIR} --suffix=".tif" XXXXXXXXXXXXXXXX)
  B_BAND=$(mktemp -q --tmpdir=${TMPDIR} --suffix=".tif" XXXXXXXXXXXXXXXX)
  A_BAND=$(mktemp -q --tmpdir=${TMPDIR} --suffix=".tif" XXXXXXXXXXXXXXXX)

  KAPPA=0

  while IFS= read COLS ROWS; do

    let KAPPA+=1

  done < $(gdalinfo ${1} | egrep '^Size' | cut -d' ' -f3- | sed -r 's/,//g')

  while IFS= read XMIN YMIN XMAX YMAX; do

    let KAPPA+=1

  done < $(cat ${CSV})

  echo "[DEBUG]: ${KAPPA}"

  gdal_edit.py -unsetnodata ${1}

  gdal_rasterize -q -of GTiff -ot Byte -burn 255 -l footprint -ts ${COLS} ${ROWS} \
    -te ${XMIN} ${YMIN} ${XMAX} ${YMAX} ${FOOTPRINT} ${A_BAND}

  gdal_calc.py -A ${1} --A_band=1 -B ${A_BAND} --B_band=1 --type=Byte --format=GTiff --overwrite \
    --quiet --NoDataValue=0 --outfile=${R_BAND} --calc="( A * ( B != 0 ) ) + ( A == 0 ) * ( B != 0 )" &

  gdal_calc.py -A ${1} --A_band=2 -B ${A_BAND} --B_band=1 --type=Byte --format=GTiff --overwrite \
    --quiet --NoDataValue=0 --outfile=${G_BAND} --calc="( A * ( B != 0 ) ) + ( A == 0 ) * ( B != 0 )" &

  gdal_calc.py -A ${1} --A_band=3 -B ${A_BAND} --B_band=1 --type=Byte --format=GTiff --overwrite \
    --quiet --NoDataValue=0 --outfile=${B_BAND} --calc="( A * ( B != 0 ) ) + ( A == 0 ) * ( B != 0 )" &

  wait

  gdal_merge.py -q -o ${1} -ot Byte -of GTiff -n 0 -a_nodata 0 -separate \
    ${R_BAND} ${G_BAND} ${B_BAND}

  gdal_edit.py -colorinterp_1 red -colorinterp_2 green -colorinterp_3 blue ${1}

  rm -f ${R_BAND} ${G_BAND} ${B_BAND} ${BBOX} ${CSV}

  return ${A_BAND}
}