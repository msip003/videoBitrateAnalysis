#!/bin/bash
# version 	  : 2.0
# Prerequsite : 1. Install "gnumeric" (Packages : gnu-free-fonts-common-20100919-3.el6.noarch.rpm,gnu-free-sans-fonts-20100919-3.el6.noarch.rpm,gnumeric-1.10.10-2.el6.1.i686.rpm,gnumeric-1.10.10-2.el6.1.x86_64.rpm,goffice-0.8.12-1.el6.i686.rpm,goffice-0.8.12-1.el6.x86_64.rpm)
# Last update : 29 nov 2018

Source=/home/ftp/tempBackup/videoFiles # source files to analyze bitrate
Blade=`hostname`
DATE=`date +"%Y%m%d_%H%M"`
LOG_PATH=/home/ftp/videoAnalysis
[ -d $LOG_PATH ] && mv -f $LOG_PATH $LOG_PATH-$DATE
[ ! -d $LOG_PATH ] && mkdir -p $LOG_PATH
function LogAndEcho()
{
	echo -e "`date` : $@" >> $LOG_PATH/scriptExec.log
	echo -e "$@"
}

# ffmpeg binary path
FFMPEG=`/bin/ls -ltr /usr/local/bin/ | /bin/awk '$NF ~ /evotranscoder/ {m=$NF} END {print "/usr/local/bin/"m}'`
## ffmpeg validation
$FFMPEG -version
[ "$?" -ne "0" ] && LogAndEcho "`date` Unable to locate FFMPEG" && exit 0;

##Source Analysis
RESULT_PATH=$LOG_PATH/REPORTS
[ ! -d $RESULT_PATH ] && mkdir -p $RESULT_PATH
Output=$RESULT_PATH/source_analysis
[ -f $Output ] && mv $Output $Output-$DATE
MEDIAINFO_PATH=$LOG_PATH/MediaInfo
[ ! -d $MEDIAINFO_PATH ] && mkdir -p $MEDIAINFO_PATH
cd $Source
ChannelList=(`ls -l | awk '/^d/ {print $NF}'`)
echo "Foldername,Duration,Width(pixels),Height(pixels),FPS,ScanType,BPP,Codec,Bitrate(kb/s),Avg.Bitrate(kb/s),Category_Level," > $Output
LogAndEcho "################### SOURCE ANALYSIS STARTED ###################"
for Channel in ${ChannelList[@]}
do
cd $Source/$Channel
	for i in `ls *.ts`;
	do
		FILE_NAME=`basename $i|cut -d. -f1`;
		LogAndEcho "Analyzing the source information of $FILE_NAME ..."
		MEDIAINFO=$MEDIAINFO_PATH/$FILE_NAME.txt
		mediainfo $i > $MEDIAINFO
		DURATION=`awk -F ':' '/Duration/ {print $NF; exit}' $MEDIAINFO`
		WIDTH=`grep  "Width" $MEDIAINFO | sed 's/[^0-9]*//g'`;
		HIGHT=`grep  "Height" $MEDIAINFO | sed 's/[^0-9]*//g'`;
		FPS=`awk  '/Frame rate/ {print $4; exit}' $MEDIAINFO`;
		SCAN_TYPE=`awk -F '[ :]' '/Scan type/ {print $NF}' $MEDIAINFO`;
		BITS_PER_PIXEL=`grep "Bits/(Pixel" $MEDIAINFO  | sed 's/[^0-9.]*//g'`;
		CODEC=`awk -F ':' '/Format/{i++}i==2 {print $NF}'  $MEDIAINFO | head -n1`;
		BITRATE=` awk -F'[^0-9]*' '/Overall bit rate/ && /kb/ {gsub("[^[:digit:]]+","");print}' $MEDIAINFO`
		[ -z $BITRATE ] && BITRATE=`awk -F'[^0-9.]*' '/Overall bit rate/ && /Mb/ {a=$2*1000;print a}' $MEDIAINFO`;
		echo -e "${FILE_NAME},${DURATION},${WIDTH},${HIGHT},${FPS},${SCAN_TYPE},${BITS_PER_PIXEL},${CODEC},${BITRATE}," >>  $Output
	done
	CHANNEL_CLIP=''$Channel'_trans_clip'
	AVG_BITRATE=`grep "^$CHANNEL_CLIP"  $Output | awk -F ',' '$9 ~ /^[0-9]+$/ {print $9}'  | awk -F ',' 'NF=1{avg += ($1 - avg) / NR;} END {print avg;}'`
	sed -i "/^$CHANNEL_CLIP/  s/,$/,$AVG_BITRATE,/" $Output
done
awk -F ',' '{ if ($(NF-1) ~ /[a-zA-Z]+$/){ print $0;} else if ($(NF-1) < 7000){ print $0 "veryLow"$4;} else if (($(NF-1) >= 7000) && ($(NF-1) < 10000)) { print $0 "Medium"$4;} else if (($(NF-1) >= 10000) && ($(NF-1) < 13000)) { print $0 "High"$4;} else if (($(NF-1) >= 13000) && ($(NF-1) < 17000)) { print $0 "Veryhigh"$4;} else if ($(NF-1) >= 17000) { print $0 "ExceptionalyHigh"$4;} else { print $0; }}' $Output > $RESULT_PATH/tmp.csv && mv -f $RESULT_PATH/tmp.csv $Output
LogAndEcho "################### SOURCE ANALYSIS COMPLETED ###################"

NO_CAP_ANALYSIS ()
{
	LogAndEcho "################### NO_CAP ANALYSIS STARTED ###################"
	cd $Source
	ChannelList=(`ls -l | awk '/^d/ {print $NF}'`)
	for CHANNEL_NAME in ${ChannelList[@]}
	do
		LogAndEcho "################### NO_CAP ANALYSIS STARTED FOR $CHANNEL_NAME STARTED ###################"
		SOURCE_PATH=$Source/$CHANNEL_NAME/"$CHANNEL_NAME"_trans_clip_*.ts #Source .ts path
		DIRNAME=$LOG_PATH/$CHANNEL_NAME/noCap_$CHANNEL_NAME #Output Directory path in current directory
		[ ! -d $DIRNAME ] && mkdir -p $DIRNAME
		CSV_SHEET=$DIRNAME/nocap_$CHANNEL_NAME #only crf and without maxrate option
		echo -e "FileName,Width,Height,CRF,FPS,MaxRate(kbps),Actual Rate(kbps),Filesize(MB),PSNR-Y,PSNR-Full,SSIM(db)" > ${CSV_SHEET}
		for i in `ls ${SOURCE_PATH}`
		do
			LogAndEcho "----------> Analyzing $i without cap started"
			FILENAME=`basename ${i}|cut -d. -f1`
			SOURCE_HEIGHT=`mediainfo ${i}|grep  "Height"| sed 's/[^0-9]*//g'`
			SOURCE_FFMPEG_INFO=$DIRNAME/${FILENAME}.txt
			${FFMPEG} -i $i 2> $SOURCE_FFMPEG_INFO 
			VIDEO_PID=`awk -F ':' '/Stream/ {print $3}' $SOURCE_FFMPEG_INFO  | nl -v 0 | awk '/Video/ {print $1}' | head -n1`
			AUDIO_PID=`awk -F ':' '/Stream/ {print $3}' $SOURCE_FFMPEG_INFO  | nl -v 0 | awk '/Audio/ {print $1}' | head -n1`
			SCAN_TYPE1=`awk -F '[ :]' '/Scan type/ {print $NF}' $LOG_PATH/MediaInfo/${FILENAME}.txt* | head -n1`
			BWDIF='bwdif=1:-1:1,split'
			[ $SCAN_TYPE1 == 'Progressive' ] && BWDIF=split
		case "${SOURCE_HEIGHT}" in
			1080) assetTranscode1080 
					cp ${CSV_SHEET} $RESULT_PATH;;
					
			720) assetTranscode720 60 
					cp ${CSV_SHEET} $RESULT_PATH;;
			480) assetTranscode480 704
					cp ${CSV_SHEET} $RESULT_PATH;;
			360) assetTranscode360 
					cp ${CSV_SHEET} $RESULT_PATH;;
		esac
		LogAndEcho "----------> Analyzing $i without cap completed"
		done
		LogAndEcho "################### NO_CAP ANALYSIS STARTED FOR $CHANNEL_NAME COMPLETED ###################"
	done
	LogAndEcho "################### NO_CAP ANALYSIS COMPLETED ###################"
}

################### WITH CAP ###################
WITH_CAP_ANALYSIS ()
{
	LogAndEcho "################### WITH_CAP ANALYSIS STARTED ###################"
	cd $Source
	ChannelList=(`ls -l | awk '/^d/ {print $NF}'`)
	for CHANNEL_NAME in ${ChannelList[@]}
	do
		LogAndEcho "################### WITH_CAP ANALYSIS STARTED FOR $CHANNEL_NAME STARTED ###################"
		SOURCE_PATH=$Source/$CHANNEL_NAME/"$CHANNEL_NAME"_trans_clip_*.ts #Source .ts path
		DIRNAME=$LOG_PATH/$CHANNEL_NAME/Realtime_$CHANNEL_NAME 
		[ ! -d $DIRNAME ] && mkdir -p $DIRNAME
		CSV_SHEET=$DIRNAME/Realtime_$CHANNEL_NAME
		echo -e "FileName,Width,Height,CRF,FPS,MaxRate(kbps),Actual Rate(kbps),Filesize(MB),PSNR-Y,PSNR-Full,SSIM(db)" > ${CSV_SHEET}
		for i in `ls ${SOURCE_PATH}`
		do
			FILENAME=`basename ${i}|cut -d. -f1`
			LogAndEcho "----------> Analyzing $i with cap started"
			SOURCE_FFMPEG_INFO=$DIRNAME/${FILENAME}.txt
			${FFMPEG} -i $i 2> $SOURCE_FFMPEG_INFO 
			VIDEO_PID=`awk -F ':' '/Stream/ {print $3}' $SOURCE_FFMPEG_INFO  | nl -v 0 | awk '/Video/ {print $1}' | head -n1`
			AUDIO_PID=`awk -F ':' '/Stream/ {print $3}' $SOURCE_FFMPEG_INFO  | nl -v 0 | awk '/Audio/ {print $1}' | head -n1`
			SOURCE_HEIGHT=`mediainfo ${i}|grep  "Height"| sed 's/[^0-9]*//g'`
			[ $SOURCE_HEIGHT -eq 480 ] && SOURCE_WIDTH=`mediainfo ${i}|grep  "Width"| sed 's/[^0-9]*//g'`
			NOCAP_SHEET=$RESULT_PATH/nocap_$CHANNEL_NAME
			BITRATE1080=`awk -F ',' '$3==1080 { sum += $7; n++ } END {sum1=sum+100; if (n > 0) print sum1 / n; }' $NOCAP_SHEET  | awk 'END { print int(($1 / 100) + 0.5) * 100 }'`
			[ $BITRATE1080 -lt 4500 ] && BITRATE1080=4500
			[ $BITRATE1080 -gt 6500 ] && BITRATE1080=6500
			BITRATE720=`awk -F ',' '$3==720 { sum += $7; n++ } END {sum1=sum+100; if (n > 0) print sum1 / n; }' $NOCAP_SHEET  | awk 'END { print int(($1 / 100) + 0.5) * 100 }'`
			[ $BITRATE720 -lt 2500 ] && BITRATE720=2500
			[ $BITRATE720 -gt 4500 ] && BITRATE720=4500
			BITRATE480=`awk -F ',' '$3==480 { sum += $7; n++ } END {sum1=sum+100; if (n > 0) print sum1 / n; }' $NOCAP_SHEET  | awk 'END { print int(($1 / 100) + 0.5) * 100 }'`
			[ $BITRATE480 -lt 950 ] && BITRATE480=950
			[ $BITRATE480 -gt 1600 ] && BITRATE480=1600
			BITRATE360=`awk -F ',' '$3==360 { sum += $7; n++ } END {sum1=sum+100; if (n > 0) print sum1 / n; }' $NOCAP_SHEET  | awk 'END { print int(($1 / 100) + 0.5) * 100 }'`
			[ $BITRATE360 -lt 600 ] && BITRATE360=600
			[ $BITRATE360 -gt 1100 ] && BITRATE360=1100
			SCAN_TYPE2=`awk -F '[ :]' '/Scan type/ {print $NF}' $LOG_PATH/MediaInfo/${FILENAME}.txt* | head -n1`
			BWDIF='bwdif=1:-1:1,split'
			[ $SCAN_TYPE2 == 'Progressive' ] && BWDIF=split
			case "${SOURCE_HEIGHT}" in
				1080) assetTranscode1080 
					cp ${CSV_SHEET} $RESULT_PATH;;
				720) assetTranscode720 60 
					cp ${CSV_SHEET} $RESULT_PATH;;
				480) assetTranscode480 $SOURCE_WIDTH
					cp ${CSV_SHEET} $RESULT_PATH;;
				360) assetTranscode360 
					cp ${CSV_SHEET} $RESULT_PATH;;
			esac
			LogAndEcho "----------> Analyzing $i with cap completed"
		done
		LogAndEcho "################### WITH_CAP ANALYSIS STARTED FOR $CHANNEL_NAME COMPLETED ###################"
	done
	LogAndEcho "################### WITH_CAP ANALYSIS COMPLETED ###################"
}

updatedataForAnalysis ()
{
    FILE_NAME=`basename $1|cut -d. -f1`
	[ "$2"  != "" ] && FILE_NAME=${FILE_NAME}_$2
	MEDIA_INFO=$DIRNAME/mediainfo_$FILENAME
	[ -f $MEDIA_INFO ] && mv $MEDIA_INFO $MEDIA_INFO-$DATE
	mediainfo $1 > $MEDIA_INFO
	WIDTH=`grep  "Width" $MEDIA_INFO | sed 's/[^0-9]*//g'`
	HEIGHT=`grep  "Height" $MEDIA_INFO | sed 's/[^0-9]*//g'`
	[ "$3" != "" ] && CRF=$3 || CRF=0
	[ "$4" != "" ] && MAXRATE=$4 || MAXRATE=0
	FPS=`awk  '/Frame rate/ {print $4; exit}' $MEDIA_INFO`
	ACTUAL_BITRATE=` awk -F'[^0-9]*' '/Overall bit rate/ && /kb/ {gsub("[^[:digit:]]+","");print}' $MEDIA_INFO`
	[ -z $ACTUAL_BITRATE ] && ACTUAL_BITRATE=`awk -F'[^0-9.]*' '/Overall bit rate/ && /Mb/ {a=$2*1000;print a}' $MEDIA_INFO`;
	PSNR_Y=`awk  -F '[ :]' '$4 ~ /PSNR/ && $6 ~ /Y/ {print $7}' "$1.txt" | tail -n 1 `
	PSNR_FULL=`grep "PSNR Mean" "$1.txt" | tail -n 1 | awk '{print $6$7$8$9$10}'`
	FILE_SIZE=`du -m "$1"| awk '{print $1}'`
	SSIM=`awk -F '[ :]' '/SSIM Mean Y:/ {print $7}' "$1.txt" | tail -n 1 `
	echo -e "${FILE_NAME},${WIDTH},${HEIGHT},${CRF},${FPS},${MAXRATE},${ACTUAL_BITRATE},${FILE_SIZE},${PSNR_Y},${PSNR_FULL},${SSIM}" >> ${CSV_SHEET}
}

assetTranscode ()
{
	if [ ! -z $BITRATE ]; then
		OUTPUT=${DIRNAME}/${FILENAME}_out_${H}_C${CRF}_F${fps}_MR${BITRATE}.ts
		fps="$fps"000/1001
		LogAndEcho "Transcoding ${FILENAME} at ${RESOLUTION} and ${fps}fps with ${BITRATE} cap started..." 
		BITRATE2=`echo $BITRATE | awk '{a=$1-128; print a}'`
		nohup ${FFMPEG} -y -loglevel info -err_detect careful -analyzeduration 8000000 -probesize 4000000 -rtbufsize 300000 -flush_packets 0 -fflags +genpts+discardcorrupt -max_delay 200000 -f mpegts -i  ${i} -filter_complex "[0:p:1:${VIDEO_PID}]$BWDIF=1[d1];[d1]scale=${W}:${H}[d2];[d2]split=1[p1];[p1]scale=${RESOLUTION}[v1]" -c:v h264 -preset veryfast -threads 0 -psnr -ssim 1 -profile:v high -level 4.1 -force_key_frames "expr:gte(t,n_forced*1)" -sc_threshold 0 -ignore_unknown -flush_packets 0  -bf 3 -b_strategy 2 -crf ${CRF} -x264opts force-cfr=1 -bsf:v h264_mp4toannexb -pix_fmt yuv420p -metadata creation_time=now -metadata service_name=${CHANNEL_NAME} -metadata service_provider="Evolution Digital" -flags +cgop+low_delay -movflags empty_moov+omit_tfhd_offset+frag_keyframe+default_base_moof -map [v1] -b:v ${BITRATE2}k -maxrate:v ${BITRATE2}k -bufsize:v ${BITRATE2}k -r:v ${fps} -map 0:p:1:${AUDIO_PID} -c:a aac -filter:a volume=2 -b:a 128k -ac 2 -ar 48000 -bsf:a aac_adtstoasc -metadata creation_time=now -flags +low_delay -movflags empty_moov+omit_tfhd_offset+frag_keyframe+default_base_moof -copyts -f mpegts ${OUTPUT} > ${OUTPUT}.txt  2>&1
		LogAndEcho "Transcoding ${FILENAME} at ${RESOLUTION} and ${fps}fps with ${BITRATE} cap completed !!!"
		updatedataForAnalysis ${OUTPUT} "" ${CRF} "${BITRATE}"
	else
		fps="$fps"000/1001
		LogAndEcho "Transcoding ${FILENAME} at ${RESOLUTION} without cap started..." 
		nohup ${FFMPEG} -y -loglevel info -err_detect careful -analyzeduration 8000000 -probesize 4000000 -rtbufsize 300000 -flush_packets 0 -fflags +genpts+discardcorrupt -max_delay 200000 -f mpegts -i  ${i} -filter_complex "[0:p:1:${VIDEO_PID}]$BWDIF=1[d1];[d1]scale=${W}:${H}[d2];[d2]split=1[p1];[p1]scale=${RESOLUTION}[v1]" -c:v h264 -preset veryfast -threads 0 -psnr -ssim 1 -profile:v high -level 4.1 -force_key_frames "expr:gte(t,n_forced*1)" -sc_threshold 0 -ignore_unknown -flush_packets 0  -bf 3 -b_strategy 2 -crf ${CRF} -x264opts force-cfr=1 -bsf:v h264_mp4toannexb -pix_fmt yuv420p -metadata creation_time=now -metadata service_name=${CHANNEL_NAME} -metadata service_provider="Evolution Digital" -flags +cgop+low_delay -movflags empty_moov+omit_tfhd_offset+frag_keyframe+default_base_moof -map [v1] -r:v ${fps} -map 0:p:1:${AUDIO_PID} -c:a aac -filter:a volume=2 -b:a 128k -ac 2 -ar 48000 -bsf:a aac_adtstoasc -metadata creation_time=now -flags +low_delay -movflags empty_moov+omit_tfhd_offset+frag_keyframe+default_base_moof -copyts -f mpegts ${OUTPUT} > ${OUTPUT}.txt  2>&1
		LogAndEcho "Transcoding ${FILENAME} at ${RESOLUTION} and ${fps}fps without cap completed !!!" 
		updatedataForAnalysis ${OUTPUT} "" ${CRF} ""
	fi
}

assetTranscode360_24 ()
{
	fps=24
	OUTPUT=${DIRNAME}/${FILENAME}_out_${H}_C${CRF}_F${fps}_MR0.ts
	assetTranscode
}

assetTranscode360 ()
{
	W=$1
	H=360
	fps=30
	CRF=23
	BITRATE=$BITRATE360
	OUTPUT=${DIRNAME}/${FILENAME}_out_${H}_C${CRF}_F${fps}_MR0.ts
	RESOLUTION=$W:$H
	assetTranscode
	assetTranscode360_24
}

assetTranscode480 ()
{
	W=$1
	H=480
	fps=30
	CRF=23
	BITRATE=$BITRATE480
	OUTPUT=${DIRNAME}/${FILENAME}_out_${H}_C${CRF}_F${fps}_MR0.ts
	RESOLUTION=$W:$H
	assetTranscode
	[ "$W" -gt 640 ] && W=640
	assetTranscode360 $W
}

assetTranscode720 ()
{
	W=1280
	H=720
	fps=$1
	CRF=19
	BITRATE=$BITRATE720
	OUTPUT=${DIRNAME}/${FILENAME}_out_${H}_C${CRF}_F${fps}_MR0.ts
	RESOLUTION=$W:$H
	assetTranscode
	assetTranscode480 704
}

assetTranscode1080_30 ()
{
	W=1920
	H=1080
	fps=30
	CRF=19
	BITRATE=$BITRATE1080
	OUTPUT=${DIRNAME}/${FILENAME}_out_${H}_C${CRF}_F${fps}_MR0.ts
	RESOLUTION=$W:$H
	assetTranscode
	assetTranscode720 30
}

assetTranscode1080 ()
{
	W=1280
	H=720
	fps=60
	CRF=19
	BITRATE=$BITRATE1080
	OUTPUT=${DIRNAME}/${FILENAME}_out_${H}_C${CRF}_F${fps}_MR0.ts
	RESOLUTION=$W:$H
	assetTranscode
	assetTranscode1080_30
}

NO_CAP_ANALYSIS
WITH_CAP_ANALYSIS

## Cumulating report
cd $Source
XLS_PATH=$LOG_PATH/FINAL_RESULT
[ ! -d $XLS_PATH ] && mkdir -p $XLS_PATH
echo "FileName,Width,Height,CRF,FPS,MaxRate(kbps),Actual Rate(kbps),Filesize(MB),PSNR-Y,PSNR-Full,SSIM(db),MaxRate(kbps),Actual Rate(kbps),Filesize(MB),PSNR-Y,PSNR-Full,SSIM(db),PSNR diff,BEST quality(%)" > $XLS_PATH/mastersheet
ChannelList=(`ls -l | awk '/^d/ {print $NF}'`)
for CHANNEL in ${ChannelList[@]}
do
	echo "FileName,Width,Height,CRF,FPS,MaxRate(kbps),Actual Rate(kbps),Filesize(MB),PSNR-Y,PSNR-Full,SSIM(db),MaxRate(kbps),Actual Rate(kbps),Filesize(MB),PSNR-Y,PSNR-Full,SSIM(db)" > $XLS_PATH/$CHANNEL
	/usr/bin/join -t ',' -o 1.1,1.2,1.3,1.4,1.5,1.6,1.7,1.8,1.9,1.10,1.11,2.6,2.7,2.8,2.9,2.10,2.11 <(/bin/sort  $LOG_PATH/REPORTS/nocap_$CHANNEL | /bin/grep -v "^FileName" | /bin/sed 's/_MR[0-9]*,/,/g' ) <(/bin/sort  $LOG_PATH/REPORTS/Realtime_$CHANNEL | /bin/grep -v "^FileName" | /bin/sed 's/_MR[0-9]*,/,/g' ) >> $XLS_PATH/$CHANNEL
	BITRATES=(`awk -F ',' '$3 !~ /Height/ {print $3}' $XLS_PATH/$CHANNEL | sort -u | tr '\n' ' '`)
	for BT in ${BITRATES[@]}
	do
		AVG_VALUES=`awk -F ',' -v b=$BT '$3 == b' $XLS_PATH/$CHANNEL | awk -F ',' '{for (i=2;i<=NF;i++){a[i]+=$i;}} END {for (i=2;i<=NF;i++){printf  a[i]/NR; printf ","};printf "\n"}'`
		PERCENTAGE=`echo $AVG_VALUES | awk -F ',' '{b=$8-$14;c=($14/$8)*100; print $0""b","c}'`
		echo "$CHANNEL,$PERCENTAGE" >> $XLS_PATH/mastersheet
	done
done

XLS_FILE=$XLS_PATH/blade$Blade-videoAnalysis.xls
/usr/bin/ssconvert --merge-to=$XLS_FILE $LOG_PATH/FINAL_RESULT/* > /dev/null 2>&1
LogAndEcho "###################################################"
LogAndEcho "FINAL REPORT available at $XLS_FILE"
LogAndEcho "###################################################"