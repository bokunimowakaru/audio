#!/bin/bash
# Internet Radio with LCD

################################################################################
# 実行する前に、お住いの国の著作権法などに十分に注意してください。
# Please pay close attention to the copyright laws of your country.
################################################################################
# 筆者が公開しているプログラムは技術的な学習や検証を目的として作成したものです。
# また、ソース内のURLについてもサンプルです。
# 掲載したURLの各サイトが配信するコンテンツの著作権については、配信サイトに確認
# ください。
# もし日本国または米国の法律に違反していることを当方が認知した場合は、速やかに
# GitHub内に保存した該当URLを削除します。当方はそれ以上の責任を負いません。
#
# The following was translated using Google translation service. If there is a
# discrepancy in the content below, the original text written in Japanese will
# take precedence.
#
# The program published by the author was created for the purpose of technical
# learning and verification.
# Also, the URL in the source is also a sample.
# Check with the distribution site for the copyright of the content distributed
# by each site of the posted URL, please.
# If I become aware that there is a violation of Japanese or US law, I will 
# promptly delete the relevant URL stored in GitHub.
# I do not take any further responsibility.

################################################################################
# 元ソース：
# https://github.com/bokunimowakaru/audio/blob/master/radio/pi/radio.sh
# https://github.com/bokunimowakaru/raspi_lcd/blob/master/example_Pi5.sh
# https://github.com/bokunimowakaru/raspi_lcd/blob/master/raspi_i2c.c
################################################################################

# 解説：
#   実行するとインターネットラジオを再生します。
#   GPIO 26に接続したボタンを押すとチャンネルを切り替えます。
#
# 詳細：
#   Radio & Jukebox
#   https://bokunimo.net/blog/raspberry-pi/3179/
#
#   DAC PCM5102A で Raspberry Pi オーディオ
#   https://bokunimo.net/blog/raspberry-pi/3123/
#
# ffmpegのインストール：
#   $ sudo apt install ffmpeg ⏎

# GPIO設定部
LCD_IO=4                        # LCDリセット用IOポート番号を設定する
BTN_IO=26                       # タクトスイッチのGPIO ポート番号

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
urln=${#urls[@]}

# ラジオ再生用の関数を定義
radio (){
    echo `date` "radio ch =" $1
    if [ $1 -ge 1 ] && [ $1 -le $urln ]; then
        url_ch=(${urls[$(($1 - 1))]})
        echo `date` "Internet Radio =" ${url_ch[0]}
        kill `pidof ffplay` &> /dev/null
        ffplay -nodisp ${url_ch[1]} 2>&1 | ${0} lcd_out &
    else
        echo `date` "ERROR radio ch" $1
    fi
}

# LCD表示用の関数を定義
lcd (){
    s=${@}                                    # 全パラメータを変数sに代入
    s1=${s:0:8}                               # 受信データの先頭8バイト
    s2=${s:8:10}                              # 9バイト目以降10バイトを抽出
    s2=${s2:0:8}                              # 8文字までに制限
    echo `date` "lcd_out =" ${s1} "/" ${s2}   # LCD出力内容を表示
    hex1=`echo -n $s1|iconv -f utf8 -t sjis|od -An -tx1|sed 's/ / 0x/g'`
    hex2=`echo -n $s2|iconv -f utf8 -t sjis|od -An -tx1|sed 's/ / 0x/g'`
    i2cset -y 1 0x3e 0x00 0x80 i
    i2cset -y 1 0x3e 0x40 ${hex1} 32 32 32 32 32 32 32 32 i
    i2cset -y 1 0x3e 0x00 0xc0 i
    i2cset -y 1 0x3e 0x40 ${hex2} 32 32 32 32 32 32 32 32 i
}

# チャンネル名（icy-description）の表示実行部
if [[ ${1} == "lcd_out" ]]; then
    echo `date` "Started Subprocess lcd_out"
    while read s; do
        s=`echo ${s}|grep "icy-description"|cut -d" " -f3-`
        if [[ -n ${s} ]]; then
            echo `date` "icy-description =" ${s}
            lcd ${s}
        fi
    done
    exit
fi

# メイン処理部 #################################################################
echo "Usage: "${0}              # プログラム名と使い方を表示する
gpio_app="pinctrl"              # GPIO制御にpinctrlを使用する for Raspberry Pi 5
# gpio_app="raspi-gpio"         # GPIO制御にraspi-gpioを使用する

# ボタン・LCD初期化処理
${gpio_app} set ${BTN_IO} ip    # ポート番号BTN_IOのGPIOを入力に設定
${gpio_app} set ${BTN_IO} pu    # ポート番号BTN_IOをプルアップ
${gpio_app} set ${LCD_IO} op    # ポート番号LCD_IOのGPIOを出力に設定
${gpio_app} set ${LCD_IO} dl    # GPIOにLレベルを出力
sleep 0.1                       # 0.1秒の待ち時間処理
${gpio_app} set ${LCD_IO} dh    # GPIOにHレベルを出力
sleep 0.1                       # 0.1秒の待ち時間処理
i2cset -y  1 0x3e 0x00 0x39  0x14  0x73 0x56 0x6c 0x38 0x0C i
sleep 0.1                       # 0.1秒の待ち時間処理
lcd "InternetRadio"             # LCDにタイトルを表示

ch=0                            # チャンネル
while true; do                  # 永久ループ
    pidof ffplay > /dev/null                # ffplayが動作しているかどうかを確認
    if [ $? -ne 0 ]; then                   # 動作していなかったとき
        echo `date` "PLAY Radio"            # PLAY Radioを表示
        ch=$(( ch + 1 ))                    # チャンネル番号に1を加算
        if [[ ${ch} -gt ${urln} ]]; then    # チャンネル数を超えていた時
            ch=1                            # チャンネル1に設定する
        fi
        lcd ${urls[$(( ch - 1 ))]}          # urlsに登録したチャンネル名を表示
        radio ${ch}                         # 関数 radioを呼び出し
        trap "kill `pidof ffplay` &> /dev/null" EXIT # 終了時にffplayを終了する
        sleep 1                             # 0.1秒の待ち時間処理
    fi
    btn=`${gpio_app} get ${BTN_IO}`         # ボタン状態を取得
    if [[ ${btn:15:2} = "lo" ]]; then       # 入力値がLレベルの時
        btn=1                               # 変数btnに1を代入
    elif [[ ${btn:15:2} = "hi" ]]; then     # 入力値がHレベルの時
        btn=0                               # 変数btnに0を代入
    else                                    # その他の場合(raspi-gpioなど)
        btn=`echo ${btn}|tr " " "\n"|grep "level="` # ボタンレベル値を取得
        btn=${btn:6:1}                      # レベル値を抽出
        if [[ -n ${btn} ]]; then            # レベル値が得られたとき
            btn=$(( ! ${btn} ))             # 変数btnの論理を反転
        else                                # 抽出できなかったとき
            btn=0                           # 変数btnに0を代入
        fi
    fi
    if [[ btn -eq 1 ]]; then                # ボタンが押された時
        echo `date` "CHANNEL Button Pressed"
        kill `pidof ffplay` &> /dev/null    # ffplayを終了
        sleep 1                             # 終了待ち・チャタリング防止
    fi
done                                        # 永久ループを繰り返す
