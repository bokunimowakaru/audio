#!/bin/bash
################################################################################
# インターネットラジオ (basicは基本機能のみ)
#   radio.sh
#   radio_basic.sh
#
#                                       Copyright (c) 2017 - 2022 Wataru KUNINO
################################################################################
# 解説：
#   実行するとインターネットラジオを再生します。
#
# 要件：
#   sudo apt install raspi-gpio

# 自動起動：
#   /etc/rc.localに追加する場合
#       su -l pi -s /bin/bash -c /home/pi/audio/radio/pi/radio.sh &
#   crontabに追加する場合
#       /home/pi/audio/radio/pi/radio.sh &
#
# 実行権限の付与が必要：
#   chmod u+x /etc/rc.local
#
# (参考文献)ネットラジオ検索：
#   https://directory.shoutcast.com/
#
# (参考文献)GPIO用コマンド
#   raspi-gpio help

AUDIO_APP="ffplay"          # インストールした再生アプリ
LCD_APP="/home/pi/audio/radio/pi/raspi_lcd" # LCD表示用。※要makeの実行
export SDL_AUDIODRIVER=alsa # オーディオ出力にALSAを使用する設定
export AUDIODEV="hw:0,0"    # aplay -lで表示されたカード番号とサブデバイス番号を入力する
BUTTON_IO="27"              # ボタン操作する場合はIOポート番号を指定する(使用しないときは0)
START_PRE=15                # 開始待機時間(OS起動待ちなど)
LOG="/dev/stdout"           # ログファイル名(/dev/stdoutで表示)

if [ "$GPIO_LIB" = "RASPI" ]; then
    sudo usermod -a -G gpio pi # GPIO使用権グループに追加 (LITE版が設定されていない)
fi

# インターネットラジオ局の登録
urls=(
    "181.fm__Power181 http://listen.livestreamingservice.com/181-power_64k.aac"
    "181.fm__UK_Top40 http://listen.livestreamingservice.com/181-uktop40_64k.aac"
    "181.fm__The_Beat http://listen.livestreamingservice.com/181-beat_64k.aac"
    "1.FM____AmTrance http://185.33.21.111:80/atr_128"
    "NHK-FM__(Osaka)_ https://radio-stream.nhk.jp/hls/live/2023509/nhkradirubkfm/master.m3u8"
    "181.fm__Pow[Exp] http://listen.livestreamingservice.com/181-powerexplicit_64k.aac"
    "181.fm__Energy93 http://listen.livestreamingservice.com/181-energy93_64k.aac"
    "181.fm__The_Box_ http://listen.livestreamingservice.com/181-thebox_64k.aac"
    "181.fm__TranceJz http://listen.livestreamingservice.com/181-trancejazz_64k.aac"
    "NHK-N1__(Osaka)_ https://radio-stream.nhk.jp/hls/live/2023508/nhkradirubkr1/master.m3u8"
)
urln=${#urls[*]}


# LCD表示用
lcd (){
    s1="Radio Musicﾌﾟﾚｲﾔ"
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
        $LCD_APP -i -w16 ${s1} > /dev/null 2>&1
        if [ -n "$s2" ]; then
            $LCD_APP -i -w16 -y2 ${s2} > /dev/null 2>&1
        fi
    fi
    echo `date` "LCD" ${s1} ${s2}
}

# ラジオ再生用の関数を定義
radio (){
    echo `date` "radio" $1 >> $LOG 2>&1
    if [ $1 -ge 1 ] && [ $1 -le $urln ]; then
        url_ch=(${urls[$(($1 - 1))]})
        lcd "InternetRadio_"${1} ${url_ch[0]}
        kill `pidof ffplay` &> /dev/null
        if [ $AUDIO_APP = "ffplay" ]; then
            ffplay -nodisp ${url_ch[1]} &> /dev/null &
        fi
    else
        echo "ERROR ch" $1 >> $LOG 2>&1
    fi
    sleep 1
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

# 初期設定
echo `date` "STARTED ---------------------" >> $LOG 2>&1
lcd
/home/pi/audio/tools/olCheck.sh >> $LOG 2>&1
echo "Please wait" $START_PRE "seconds."    # OS起動待ち
while [ $START_PRE -gt 0 ]; do
    sleep 1
    START_PRE=$((START_PRE -1))
    echo -n "."
done
echo

button
while [ $? -eq 0 ]; do
    echo `date` "configuring GPIO" >> $LOG 2>&1
    raspi-gpio set ${BUTTON_IO} ip pu
    sleep 1
    button
done

# ループ処理
ch=1
radio $ch
while true; do
    button
    if [ $? -eq 0 ]; then
        echo `date` "button is pressed" >> $LOG 2>&1
        kill `pidof ffplay`
        sleep 1
        button
        if [ $? -eq 0 ]; then
            sleep 2
            button
            if [ $? -eq 0 ]; then
                date >> $LOG 2>&1
                echo "shutdown -h now" >> $LOG 2>&1
                sudo shutdown -h now # 動作確認してから変更すること
                exit 0
            fi
        fi
        ch=$((ch + 1))
        if [ $ch -gt $urln ]; then
            ch=1
        fi
        radio $ch
    fi
    sleep 0.05
done
exit
