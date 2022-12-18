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
# 自動起動：
#   /etc/rc.localに追加する場合
#       su -l pi -s /bin/bash -c /home/pi/audio/pi/radio.sh &
#   crontabに追加する場合
#       /home/pi/audio/pi/radio.sh &
#
# 実行権限の付与が必要：
#   chmod u+x /etc/rc.local
#
# ネットラジオ検索(参考文献)：
#   https://directory.shoutcast.com/

AUDIO_APP="ffplay"          # インストールした再生アプリ
export SDL_AUDIODRIVER=alsa # オーディオ出力にALSAを使用する設定
export AUDIODEV="hw:1,0"    # aplay -lで表示されたカード番号とサブデバイス番号を入力する
BUTTON_IO="27"              # ボタン操作する場合はIOポート番号を指定する(使用しないときは0)
LOG="/dev/stdout"           # ログファイル名(/dev/stdoutで表示)

# インターネットラジオ局の登録
urls=(
    "1:181.fmPower181 http://listen.livestreamingservice.com/181-power_64k.aac"
    "2:181.fmUK_Top40 http://listen.livestreamingservice.com/181-uktop40_64k.aac"
    "3:181.fmThe_Beat http://listen.livestreamingservice.com/181-beat_64k.aac"
    "4:1.FM__AmTrance http://185.33.21.111:80/atr_128"
    "5:NHK-FM(Osaka)_ https://radio-stream.nhk.jp/hls/live/2023509/nhkradirubkfm/master.m3u8"
    "6:181.fmPow[Exp] http://listen.livestreamingservice.com/181-powerexplicit_64k.aac"
    "7:181.fmEnergy93 http://listen.livestreamingservice.com/181-energy93_64k.aac"
    "8:181.fmThe_Box_ http://listen.livestreamingservice.com/181-thebox_64k.aac"
    "9:181.fmTranceJz http://listen.livestreamingservice.com/181-trancejazz_64k.aac"
    "0:NHK-N1(Osaka)_ https://radio-stream.nhk.jp/hls/live/2023508/nhkradirubkr1/master.m3u8"
)
urln=${#urls[*]}

# ラジオ再生用の関数を定義
radio (){
    echo `date` "radio" $1 >> $LOG 2>&1
    if [ $1 -ge 1 ] && [ $1 -le $urln ]; then
        url_ch=(${urls[$(($1 - 1))]})
        kill `pidof ffplay` &> /dev/null
        if [ $AUDIO_APP = "ffplay" ]; then
            ffplay -nodisp ${url_ch[1]} &> /dev/null &
        fi
    else
        echo "ERROR ch" $1 >> $LOG 2>&1
    fi
    sleep 1
}

# ボタン状態を取得
button (){
    if [ $(($BUTTON_IO)) -le 0 ]; then
        return 1
    else
        return $((`cat /sys/class/gpio/gpio${BUTTON_IO}/value`))
    fi
}

# 初期設定
echo `date` "STARTED ---------------------" >> $LOG 2>&1
/home/pi/audio/tools/olCheck.sh >> $LOG 2>&1
pause=15
echo "Please wait" $pause "seconds."    # OS起動待ち
while [ $pause -gt 0 ]; do
    sleep 1
    pause=$((pause -1))
    echo -n "."
done
echo

if [ $(($BUTTON_IO)) -gt 0 ]; then
    raspi-gpio set ${BUTTON_IO} pn >> $LOG 2>&1
    sleep 1
    echo ${BUTTON_IO} > /sys/class/gpio/export &>> $LOG
    sleep 3
    echo in > /sys/class/gpio/gpio${BUTTON_IO}/direction &>> $LOG
    button
    while [ $? -eq 0 ]; do
        echo `date` "waiting for your button release" >> $LOG 2>&1
        sleep 5
        button
    done
fi

# ループ処理
ch=1
radio $ch
while true; do
    button
    if [ $? -eq 0 ]; then
        echo `date` "button is pressed" >> $LOG 2>&1
        sleep 3
        button
        if [ $? -eq 0 ]; then
            date >> $LOG 2>&1
            echo "shutdown -h now" >> $LOG 2>&1
            kill `pidof ffplay`
            # sudo shutdown -h now # 動作確認してから変更すること
            exit 0
        fi
        ch=$((ch + 1))
        if [ $ch -gt $urln ]; then
            ch=1
        fi
        radio $ch
    fi
    sleep 0.1
done
exit
