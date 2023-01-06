#!/bin/bash
################################################################################
# インターネットラジオ＋ジュークボックス (basicは基本機能のみ)
#   radio.sh
#   radio_basic.sh
#
#                                       Copyright (c) 2022 - 2023 Wataru KUNINO
################################################################################
# 解説：
#   実行するとインターネットラジオを再生します。
#
# 詳細：
#   Radio & Jukebox
#   https://bokunimo.net/blog/raspberry-pi/3179/
#
#   DAC PCM5102A で Raspberry Pi オーディオ
#   https://bokunimo.net/blog/raspberry-pi/3123/
#
# 要件：
#   本ソフトのインストール($よりも後ろのコマンドを入力)：
#   $ cd ⏎
#   $ sudo apt install raspi-gpio ⏎ (古いOS使用時)
#   $ sudo apt install alsa-utils ⏎ (LITE版OS使用時)
#   $ sudo apt install ffmpeg ⏎
#   $ sudo apt install git ⏎ (LITE版OS使用時)
#   $ git clone https://bokunimo.net/git/audio ⏎
#   $ cd audio/radio/pi ⏎
#   $ make clean ⏎
#   $ make ⏎
#   $ ./radio.sh ⏎
#   (音が出ないときは、下記のカード番号、デバイス番号を変更して再実行)
#   $ vi audio/radio/pi/radio.sh ⏎
#       export AUDIODEV="hw:1,0"
#
# (参考) 自動起動：
#   /etc/rc.localに追加する場合
#       su -l pi -s /bin/bash -c /home/pi/audio/radio/pi/radio.sh &
#   crontabに追加する場合
#       @reboot /home/pi/audio/radio/pi/radio.sh &
#
#   実行権限の付与が必要：
#       $ chmod u+x /etc/rc.local ⏎
#
# (参考) ファイル共有サーバ Samba のインストール
#   $ sudo apt install samba ⏎
#   $ sudo mousepad /etc/samba/smb.conf & ⏎
#       (下記を追加)
#       [music]
#          comment = Music Folder
#          path = /home/pi/Music
#          read only = no
#          create mask = 0644
#   $ sudo pdbedit -a pi ⏎
#   new password: (ファイル共有用パスワード) ⏎
#   retype new password: (ファイル共有用パスワード) ⏎
#   $ mkdir -p /home/pi/Music ⏎
#
#   Windowsのエクスプローラーから以下でアクセスできるようになる
#       \\(IPアドレス)\music
#
# (参考文献)ネットラジオ検索：
#   https://directory.shoutcast.com/
#
# (参考情報)LCD表示用プログラム raspi_lcd の使い方：
#   $ cd ~/audio/radio/pi ⏎
#   $ ./raspi_lcd -h ⏎
#
# (参考文献)GPIO用コマンド
#   $ raspi-gpio help ⏎
#

export SDL_AUDIODRIVER=alsa # オーディオ出力にALSAを使用する設定
export AUDIODEV="hw:0,0"    # aplay -lで表示されたカード番号とサブデバイス番号を入力する
FILEPATH="/home/pi/Music"   # MusicBox用のファイルパス
TEMP_DIR="/radio_sh_tmp"    # MusicBox用のファイルパス
BUTTON_IO="27"              # ボタン操作する場合はIOポート番号を指定する(使用しないときは0)
BUTTON_MODE_IO="22"         # モード切替ボタン(使用しないときは0)
LCD_IO="16"                 # LCD用電源用IOポート番号を指定する
START_PRE=10                # 開始待機時間(OS起動待ち・インターネット接続待ち時間)

AUDIO_APP="ffplay"                          # インストールした再生アプリ
LCD_APP="/home/pi/audio/radio/pi/raspi_lcd" # LCD表示用。※要makeの実行
LOG="/home/pi/audio/radio/pi/radio.log"     # ログファイル名(/dev/stdoutでコンソール表示)

if [ "$GPIO_LIB" = "RASPI" ]; then
    sudo usermod -a -G gpio pi # GPIO使用権グループに追加 (LITE版が設定されていない)
fi

# 再生モード
modes=(
    "InternetRadio"
    "MusicBox"
)
moden=${#modes[*]}

# インターネットラジオ局の登録
urls=(
    "181.fm__Power181 http://listen.livestreamingservice.com/181-power_64k.aac"
    "181.fm__UK_Top40 http://listen.livestreamingservice.com/181-uktop40_64k.aac"
    "181.fm__The_Beat http://listen.livestreamingservice.com/181-beat_64k.aac"
    "1.FM_AmsteTrance http://185.33.21.111:80/atr_128"
    "NHK-FM__(Osaka)_ https://radio-stream.nhk.jp/hls/live/2023509/nhkradirubkfm/master.m3u8"
    "181.fm__Pow[Exp] http://listen.livestreamingservice.com/181-powerexplicit_64k.aac"
    "181.fm__Energy93 http://listen.livestreamingservice.com/181-energy93_64k.aac"
    "181.fm__The_Box_ http://listen.livestreamingservice.com/181-thebox_64k.aac"
    "181.fm_TranceJaz http://listen.livestreamingservice.com/181-trancejazz_64k.aac"
    "NHK-N1__(Osaka)_ https://radio-stream.nhk.jp/hls/live/2023508/nhkradirubkr1/master.m3u8"
)
urln=${#urls[*]}

date (){
    /usr/bin/date +"%Y/%m/%d %H:%M:%S"
}

# LCD初期化用
lcd_reset (){
    echo -n `date` "LCD reset GPIO"${LCD_IO} >> $LOG 2>&1
    if [ ${LCD_IO} -ge 0 ]; then
        # raspi-gpio set 3 ip pu                # PORT_SCL
        # raspi-gpio set 2 ip pu                # PORT_SDA
        while [ "`raspi-gpio get ${LCD_IO}|awk '{print $5}'|sed 's/func=//g'`" = "INPUT" ]; do
            # GPIOの出力設定が効かないことがあるので whileで出力に切り替わるまで繰り返す
            raspi-gpio set ${LCD_IO} op pn dl   # ouput
            sleep 1
            echo -n "." >> $LOG 2>&1
        done
        raspi-gpio set ${LCD_IO} dl # RESET and VDD OFF
        sleep 0.2                   # 電源を落ち切らせるために延長(本来はsleep 0.04 )
        raspi-gpio set ${LCD_IO} dh # 電源ON
    fi
    echo >> $LOG 2>&1
    sleep 0.1
}

# LCD表示用
lcd (){
    s1="Radio&Musicﾌﾟﾚｲﾔ"
    s2="by ﾎﾞｸﾆﾓﾜｶﾙRasPi"
    #   0123456789012345
    if [ "$#" -ge 1 ] && [ -n "$1" ]; then
        s1=`echo $1| tr '_' ' '`
        if [ "$#" -ge 2 ]; then
            s2=`echo $2| tr '_' ' '`
        else 
            s2=""
        fi
    fi
    if [ -n "$LCD_APP" ]; then
        if [ -n "${s2}" ]; then
            $LCD_APP -i -w16 -r${LCD_IO} ${s1} > /dev/null 2>&1
            $LCD_APP -i -w16 -r${LCD_IO} -y2 ${s2} > /dev/null 2>&1
        else
            $LCD_APP -i -w16 -r${LCD_IO} -y1 ${s1} > /dev/null 2>&1
        fi
    fi
    echo `date` "LCD" ${s1} "/" ${s2} >> $LOG 2>&1
}

# ラジオ再生用の関数を定義
radio (){
    echo `date` "radio" $1 >> $LOG 2>&1
    if [ $1 -ge 1 ] && [ $1 -le $urln ]; then
        url_ch=(${urls[$(($1 - 1))]})
        lcd_s2=${url_ch[0]}
        lcd "InternetRadio_"${1} ${lcd_s2}
        kill `pidof ffplay` &> /dev/null
        if [ $AUDIO_APP = "ffplay" ]; then
            ffplay -nodisp ${url_ch[1]} &> /dev/null &
        fi
    else
        echo "ERROR radio ch" $1 >> $LOG 2>&1
    fi
    # sleep 0.1
}

# Jukebox用の関数を定義
music_box (){
    echo `date` "music_box" $1 >> $LOG 2>&1
    if [ $1 -ge 1 ] && [ $1 -le $file_max ]; then
        lcd_s1=`grep -i artist "${FILEPATH}${TEMP_DIR}/${filen}.txt"|cut -d"=" -f2|head -1`
        lcd_s2=`grep -i title "${FILEPATH}${TEMP_DIR}/${filen}.txt"|cut -d"=" -f2|head -1`
        if [ -z "${lcd_s1}" ]; then
            lcd_s1="MusicBox_File"${1}
        fi
        if [ -z "${lcd_s2}" ]; then
            lcd_s2="no title"
        fi
        lcd "${lcd_s1}" "${lcd_s2}"
        kill `pidof ffplay` &> /dev/null
        if [ $AUDIO_APP = "ffplay" ]; then
            ffplay -nodisp -autoexit ${FILEPATH}${TEMP_DIR}/${filen}.lnk &> /dev/null &
        fi
    else
        echo "ERROR music_box ch" $1 >> $LOG 2>&1
    fi
    # sleep 0.1
}

play (){
    if [ $mode -eq 1 ]; then
        ch=$((ch + $1))
        if [ $ch -gt $urln ]; then
            ch=1
        fi
        radio $ch
    elif [ $mode -eq 2 ]; then
        filen=$((filen + $1))
        if [ $filen -gt $file_max ]; then
            filen=1
        fi
        music_box $filen
    fi
    SECONDS=0
}

# ボタン状態を取得 (取得できないときは0,BUTTON_IO未設定時は1)
button (){
    if [ $(($BUTTON_IO)) -le 0 ]; then
        return 1
    else
        return $((`raspi-gpio get ${BUTTON_IO}|awk '{print $3}'|sed 's/level=//g'`))
        # return $((`cat /sys/class/gpio/gpio${BUTTON_IO}/value`))
    fi
}

button_mode (){
    if [ $(($BUTTON_MODE_IO)) -le 0 ]; then
        return 1
    else
        return $((`raspi-gpio get ${BUTTON_MODE_IO}|awk '{print $3}'|sed 's/level=//g'`))
    fi
}

button_shutdown (){
    ret=-1
    if [ $(($BUTTON_MODE_IO)) -gt 0 ]; then
        button_mode
        ret=$?
    elif [ $(($BUTTON_IO)) -gt 0 ]; then
        sleep 0.3
        button
        ret=$?
    fi
    if [ $ret -eq 0 ]; then
        lcd "ﾎﾞﾀﾝ_ｦ_ｵｼﾂﾂﾞｹﾙﾄ" "ｼｬｯﾄﾀﾞｳﾝ_ｼﾏｽ"
        sleep 2
        if [ $(($BUTTON_MODE_IO)) -gt 0 ]; then
            button_mode
            ret=$?
        elif [ $(($BUTTON_IO)) -gt 0 ]; then
            button
            ret=$?
        fi
        if [ $ret -eq 0 ]; then
            lcd "Shuting down..." "Please wait"
            date >> $LOG 2>&1
            echo "shutdown -h now" >> $LOG 2>&1
            sudo shutdown -h now
            exit 0
        fi
    fi
}

# MusicBox用 ファイル用リンク作成
music_file_list (){
    ls -1 -t ${FILEPATH}/*.flac ${FILEPATH}/*.mp3 > ${FILEPATH}${TEMP_DIR}/list.txt
    i="none"
    if [ -e ${FILEPATH}${TEMP_DIR}/list.txt~ ]; then
        i=`diff ${FILEPATH}${TEMP_DIR}/list.txt ${FILEPATH}${TEMP_DIR}/list.txt~`
    fi
    if [ "${i}" != "" ] || [ $# -ge 1 ] ; then
        lcd "ﾌｧｲﾙ_ﾘｽﾄ_ｻｸｾｲﾁｭｳ" "${FILEPATH}"
        rm -f ${FILEPATH}${TEMP_DIR}/*.lnk ${FILEPATH}${TEMP_DIR}/[1-9]*.txt
        i=1
        SECONDS=0
        ls -1 -t ${FILEPATH}/*.flac ${FILEPATH}/*.mp3 2> /dev/null | while read filename; do
            name=`echo ${filename}|rev|cut -d'.' -f2|cut -d'/' -f1|rev`
            ext=`echo ${filename}|rev|cut -d'.' -f1|rev`
            ln -s "${filename}" "${FILEPATH}${TEMP_DIR}/${i}.lnk"
            # https://www.ffmpeg.org/ffmpeg-formats.html#Metadata-1
            ffmpeg -nostdin -i "${FILEPATH}${TEMP_DIR}/${i}.lnk" -f ffmetadata "${FILEPATH}${TEMP_DIR}/${i}.txt" &> /dev/null
            type=`file "${FILEPATH}${TEMP_DIR}/${i}.txt"|cut -d" " -f2`
            if [ "${type}" != "UTF-8" ] && [ "${type}" != "ASCII" ]; then
                mv "${FILEPATH}${TEMP_DIR}/${i}.txt" "${FILEPATH}${TEMP_DIR}/${i}.txt~"
                iconv -f sjis -t utf8 "${FILEPATH}${TEMP_DIR}/${i}.txt~" > "${FILEPATH}${TEMP_DIR}/${i}.txt"
            fi
            artist=`echo ${name}|sed "s/ - /|/g"|cut -d"|" -f1`
            title=`echo ${name}|sed "s/ - /|/g"|cut -d"|" -f2|cut -d"." -f1`
            echo "filename_artist="${artist} >> "${FILEPATH}${TEMP_DIR}/${i}.txt"
            echo "filename_title="${title} >> "${FILEPATH}${TEMP_DIR}/${i}.txt"
            echo `date` "Metadata" ${i} "ARTIST" `grep -i artist "${FILEPATH}${TEMP_DIR}/${i}.txt"|cut -d"=" -f2|head -1` >> $LOG 2>&1
            echo `date` "Metadata" ${i} "TITLE" `grep -i title "${FILEPATH}${TEMP_DIR}/${i}.txt"|cut -d"=" -f2|head -1` >> $LOG 2>&1
            i=$(( i + 1 ))
        done
    fi
    file_max=$((`ls -t ${FILEPATH}${TEMP_DIR}/*.lnk|head -1|rev|cut -d"/" -f1|rev|cut -d"." -f1`))
    cp -f ${FILEPATH}${TEMP_DIR}/list.txt ${FILEPATH}${TEMP_DIR}/list.txt~
}

# 初期設定
echo `date` "STARTED ---------------------" >> $LOG 2>&1
lcd_reset >> $LOG 2>&1
lcd >> $LOG 2>&1
echo -n `date`" " >> $LOG 2>&1
/home/pi/audio/tools/olCheck.sh|tr "\n" " " >> $LOG 2>&1
echo >> $LOG 2>&1
file_max=0
mkdir -p ${FILEPATH}${TEMP_DIR}
music_file_list
echo `date` "MusicBox:" ${file_max} "files" >> $LOG 2>&1

# OS起動・インターネット接続待ち
echo -n `date` "Please wait" $START_PRE "seconds." >> $LOG 2>&1
while [ $START_PRE -gt $SECONDS ]; do
    sleep 1
    echo -n "." >> $LOG 2>&1
done
echo >> $LOG 2>&1

# ボタン入力用GPIO設定
button
while [ $? -eq 0 ]; do
    echo `date` "configuring GPIO" >> $LOG 2>&1
    raspi-gpio set ${BUTTON_IO} ip pu
    sleep 1
    button
done

button_mode
while [ $? -eq 0 ]; do
    echo `date` "configuring GPIO" >> $LOG 2>&1
    raspi-gpio set ${BUTTON_MODE_IO} ip pu
    sleep 1
    button_mode
done

# メイン処理
ch=1
filen=1
mode=1
lcd_s2="no title" # 再生中の曲名
lcd_reset >> $LOG 2>&1 # 起動時に実行しているがOS起動が未完了だった可能性もあるので再実行
play 0
sleep 5 # 初回再生時のインターネット接続待ち時間(初回時のネットワーク接続時間を考慮)
SECONDS=0

# ループ処理
while true; do
    sec_prev=$SECONDS
    while [ $sec_prev -eq $SECONDS ]; do
        button_mode
        if [ $? -eq 0 ]; then
            echo `date` "[mode] button is pressed" >> $LOG 2>&1
            mode=$((mode + 1))
            if [ $mode -gt $moden ]; then
                # lcd_reset >> $LOG 2>&1  # LCD動作が不安定なときに有効にする
                mode=1
            fi
            sleep 0.3
            button
            if [ $? -eq 0 ]; then  # modeとnextの両方のボタンが押されていた場合にファイル・リスト化処理を実行
                music_file_list force
                echo `date` "MusicBox:" ${file_max} "files" >> $LOG 2>&1
            else
                button_shutdown
            fi
            play 0
        fi
        button
        if [ $? -eq 0 ]; then
            echo `date` "[next] button is pressed" >> $LOG 2>&1
            kill `pidof ffplay`
            play 1
            button_shutdown
        fi
        sleep 0.03
    done
    pidof ffplay > /dev/null
    if [ $? -ne 0 ]; then
        echo `date` "[pidof] detected no music" >> $LOG 2>&1
        play 1
    fi
    if [ $SECONDS -gt 60 ]; then
        SECONDS=$((`date |cut -d":" -f3`))
        # echo `date` "set SECONDS="${SECONDS} >> $LOG 2>&1
        # lcd_reset >> $LOG 2>&1  # LCD動作が不安定なときに有効にする
        lcd "`date|cut -c1-16`" "${lcd_s2}" >> $LOG 2>&1
    fi
done
exit
