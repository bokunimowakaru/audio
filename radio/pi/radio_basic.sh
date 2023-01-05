#!/bin/bash
################################################################################
# インターネットラジオ (basicは基本機能のみ)
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
#   $ sudo apt install alsa-utils ⏎ (LITE版OS使用時)
#   $ sudo apt install ffmpeg ⏎
#   $ sudo apt install git ⏎ (LITE版OS使用時)
#   $ git clone https://bokunimo.net/git/audio ⏎
#   $ cd audio/radio/pi ⏎
#   $ ./radio.sh ⏎
#   (音が出ないときは、下記のカード番号、デバイス番号を変更して再実行)
#   $ vi audio/radio/pi/radio.sh ⏎
#       export AUDIODEV="hw:1,0"
#
# (参考文献)ネットラジオ検索：
#   https://directory.shoutcast.com/
#
# (参考文献)GPIO用コマンド
#   $ raspi-gpio help ⏎
#

export SDL_AUDIODRIVER=alsa # オーディオ出力にALSAを使用する設定
export AUDIODEV="hw:0,0"    # aplay -lで表示されたカード番号とサブデバイス番号を入力する
BUTTON_IO="27"              # ボタン操作する場合はIOポート番号を指定する(使用しないときは0)

AUDIO_APP="ffplay"                          # インストールした再生アプリ
LOG="/home/pi/audio/radio/pi/radio.log"     # ログファイル名(/dev/stdoutでコンソール表示)

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

# ラジオ再生用の関数を定義
radio (){
    echo `date` "radio" $1 >> $LOG 2>&1
    if [ $1 -ge 1 ] && [ $1 -le $urln ]; then
        url_ch=(${urls[$(($1 - 1))]})
        echo "InternetRadio_"${1} ${url_ch[0]}
        kill `pidof ffplay` &> /dev/null
        if [ $AUDIO_APP = "ffplay" ]; then
            ffplay -nodisp ${url_ch[1]} &> /dev/null &
        fi
    else
        echo "ERROR radio ch" $1 >> $LOG 2>&1
    fi
    # sleep 0.1
}

play (){
    ch=$((ch + $1))
    if [ $ch -gt $urln ]; then
        ch=1
    fi
    radio $ch
    SECONDS=0
}

# ボタン状態を取得 (取得できないときは0,BUTTON_IO未設定時は1)
button (){
    if [ $(($BUTTON_IO)) -le 0 ]; then
        return 1
    else
        return $((`raspi-gpio get ${BUTTON_IO}|awk '{print $3}'|sed 's/level=//g'`))
    fi
}

button_shutdown (){
    ret=-1
    if [ $(($BUTTON_IO)) -gt 0 ]; then
        sleep 0.3
        button
        ret=$?
    fi
    if [ $ret -eq 0 ]; then
        echo "ﾎﾞﾀﾝ ｦ ｵｼﾂﾂﾞｹﾙﾄ" "ｼｬｯﾄﾀﾞｳﾝ ｼﾏｽ"
        sleep 2
        if [ $(($BUTTON_IO)) -gt 0 ]; then
            button
            ret=$?
        fi
        if [ $ret -eq 0 ]; then
            echo "Shuting down..." "Please wait"
            date >> $LOG 2>&1
            echo "shutdown -h now" >> $LOG 2>&1
            sudo shutdown -h now
            exit 0
        fi
    fi
}

# 初期設定
echo `date` "STARTED ---------------------" >> $LOG 2>&1

# ボタン入力用GPIO設定
button
while [ $? -eq 0 ]; do
    echo `date` "configuring GPIO" >> $LOG 2>&1
    raspi-gpio set ${BUTTON_IO} ip pu
    sleep 1
    button
done

# メイン処理
ch=1
play 0
sleep 5
SECONDS=0

# ループ処理
while true; do
    sec_prev=$SECONDS
    while [ $sec_prev -eq $SECONDS ]; do
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
done
exit
