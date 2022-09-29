###############################################################################
# Stereo Audio Peak Meter for Raspberry Pi Pico
###############################################################################
# キャラクタ液晶(LCD)にレベルメータ表示を行います
#
#                                              Copyright (c) 2022 Wataru KUNINO
###############################################################################

# 回路図は meter_schematic.png を参照してください。

aqm1602 = 0x3E                          # LCD AQM1602のI2Cアドレス

from machine import ADC,Pin,PWM,I2C     # ライブラリmachineのADC等を組み込む
from utime import sleep,ticks_us,ticks_diff # μtimeからsleep等を組み込む
from math import log10                  # 対数変換用モジュールを組み込む

window = 1024                           # 1回あたりの計測サンプル数
display = 'AC'                          # メータ切り替え
dispAcMaxMv = 1000                      # AC入力電圧(mV rms)
dispAcRangeDb = 40                      # レベルメータ表示範囲(dB)
dispScale = 4                           # 罫線のセル間隔(0～8,14,15)
peakMode = 'voltage'                    # 電力尖頭値=power,電圧尖頭値=voltage

# LED 初期化処理
led = PWM(Pin(25, Pin.OUT))             # PWM出力用インスタンスledを生成
led.freq(60)

# ADC 初期化処理
adc0 = ADC(0)                           # ADCポート0(Pin31)用adc0を生成
adc1 = ADC(1)                           # ADCポート1(Pin32)用adc1を生成

# LCD 初期化処理
lcd_vdd = Pin(3, Pin.OUT)               # GP3をAQM1602のV+ピンに接続
lcd_i2c = I2C(0, scl=Pin(5),sda=Pin(4)) # GP5をAQM1602のSCL,GP4をSDAに接続
lcd_vdd.value(0)                        # V+に0Vを出力
sleep(0.5)                              # リセット・ホールド
lcd_vdd.value(1)                        # V+用に3.3Vを出力
sleep(0.2)                              # 起動待ち時間
lcd_i2c.writeto_mem(aqm1602, 0x00, b'\x39\x14\x73\x5E\x6C\x38\x0C')
font_lv = [[
    b'\x00\x01\x00\x01\x00\x01\x00\x15',
    b'\x18\x19\x18\x19\x18\x19\x18\x15',
    b'\x1B\x1B\x1B\x1B\x1B\x1B\x1B\x15',
    b'\x03\x03\x03\x03\x03\x03\x03\x15'
],[
    b'\x00\x01\x00\x01\x00\x01\x00\x01',
    b'\x18\x19\x18\x19\x18\x19\x00\x01',
    b'\x1B\x1B\x1B\x1B\x1B\x1B\x00\x01',
    b'\x03\x03\x03\x03\x03\x03\x00\x01'
],[
    b'\x01\x01\x00\x01\x01\x00\x01\x01',
    b'\x19\x19\x18\x19\x19\x18\x01\x01',
    b'\x1B\x1B\x1B\x1B\x1B\x1B\x01\x01',
    b'\x03\x03\x03\x03\x03\x03\x01\x01'
]]
lcd_i2c.writeto_mem(aqm1602, 0x00, bytes([0x40])) # CGRAM address 0x00～0x02
if dispScale == 0:                      # スケール表示なしの時
    for j in range(4):                  # LCD制御 フォント4文字の転送
        lcd_i2c.writeto_mem(aqm1602, 0x40, font_lv[0][j]) # フォント
else:                                   # スケール表示ありの時
    for j in range(8):                  # LCD制御 フォント8文字の転送
        lcd_i2c.writeto_mem(aqm1602, 0x40, font_lv[1 if j<4 else 2][j%4])

def lcdPrint(y, text):                  # LCDに文字を表示する関数
    if y == 0:                                      # LCDの1行目
        lcd_i2c.writeto_mem(aqm1602, 0x00, b'\x80') # 1行目のアドレスを設定
    else:                                           # LCDの2行目
        lcd_i2c.writeto_mem(aqm1602, 0x00, b'\xC0') # 2行目のアドレスを設定
    lcd_i2c.writeto_mem(aqm1602, 0x40, bytearray(text)) # バイト列に変換して転送

def calc_volt2db(volt):                 # dB電圧を0～32の表示尺で応答する
    i = int((20 * log10(volt/dispAcMaxMv) + dispAcRangeDb)/dispAcRangeDb * 32)
    if i < 0:
        i = 0
    if i > 32:
        i = 32
    return i

led.duty_u16(0xffff)
lcdPrint(0, 'Audio Peak Meter')
lcdPrint(1, 'by Wataru Kunino')
sleep(3);
led.duty_u16(0x0000)

peak_i = 0
peakLv = [0, 0]
peakDb = [0, 0]
text = bytearray(16)
while True:                             # 繰り返し処理
    vals = [[],[]]
    valSum = [0, 0]
    valDc = [0, 0]
    valAc = [0, 0]
    voltDc = [0.0, 0.0]
    voltAc = [0.0, 0.0]
    time_start = ticks_us()
    for i in range(window):
        adc = adc0.read_u16()
        valSum[0] += adc
        vals[0].append(adc)             # ADCから値を取得して変数valに代入
        adc = adc1.read_u16()
        valSum[1] += adc
        vals[1].append(adc)             # ADCから値を取得して変数valに代入
    freq_adc = round(1000 * window / ticks_diff(ticks_us(),time_start),1)
    peak_i += 1
    for ch in range(2):
        valDc[ch] = int(valSum[ch] / window + 0.5)
        if peakMode == 'power':                     # 尖頭電力メータ
            acSum = 0
            for i in range(window):                 # 区間エネルギー計算
                acSum += abs(vals[ch][i] - valDc[ch])
            valAc[ch] = int(acSum / window + 0.5)   # サンプル数で除算しPowerに
        elif peakMode == 'voltage':                 # 尖頭電圧メータ
            acVpp = 0
            for i in range(window - 1): # ピーク演算（簡易ノイズフィルタ付）
                vpp = abs(vals[ch][i] + vals[ch][i+1] - 2 * valDc[ch])
                if vpp > acVpp:
                    acVpp = vpp
            valAc[ch] = int(acVpp / 2 / 1.41421356 + 0.5)
        voltDc[ch] = valDc[ch] * 3300 / 65535       # 直流分ADC値を電圧(mV)に変換
        voltAc[ch] = valAc[ch] * 3300 / 65535       # 交流分ADC値を電圧(mV)に変換
        if peak_i > 16:
            peakLv[ch] = voltAc[ch]
            if ch >= 1:
                peak_i = 0
        if peakLv[ch] < voltAc[ch]:
            peakLv[ch] = voltAc[ch]
            peakDb[ch] = calc_volt2db(voltAc[ch])
        if display == 'AC':
            level = calc_volt2db(voltAc[ch])
            if level < 0:
                level = 0
            if level > dispAcRangeDb:
                level = dispAcRangeDb
            for i in range(16):
                i22 = i * 2 + 1                 # セルの右側に相当するレベル値
                if i < level // 2:              # セル位置がレベル未満の時
                    text[i] = 0x02              # セルの両側を点灯
                elif i == level // 2:           # セル位置がレベル位置の時
                    if i22 == level or i22 == peakDb[ch]:   # セルの右までの時
                        text[i] = 0x02          # セルの両側を点灯
                    else:                       # (セルの左までの時)
                        text[i] = 0x01          # セルの左側を点灯
                elif i > 0 and i == peakDb[ch] // 2: # ピーク単独表示位置の時
                    if i22 == peakDb[ch]:       # ピーク位置が右側のとき
                        text[i] = 0x03          # セルの右側のみ単独点灯
                    else:                       # (ピーク位置が左側の時)
                        text[i] = 0x01          # セルの左側を点灯
                else:                           # 点灯条件に該当しないとき
                    text[i] = 0x00              # 非点灯表示
                if dispScale > 0 and i % dispScale == dispScale - 1:
                    text[i] += 0x04
            lcdPrint(ch, text)
            print('Fs(kHz)='+str(freq_adc),'AC(mV)='+str(round(voltAc[ch])),'Peak(mV)='+str(round(peakLv[ch])),'Lv='+str(level))
    led.duty_u16((valAc[0]+valAc[1])//2)                   # LEDを点灯する

###############################################################################
# ADC接続方法: 直流カットC=1u～10uFとプルアップ抵抗R=33kΩ経由で下記に接続する
##############################
# Audio   # Pico # GPIO (ADC)
##############################
#    Lch  #  31  # ADC0(GP26)
#    Rch  #  32  # ADC1(GP27)

###############################################################################
# AE-AQM0802A, AE-AQM1602A, AQM1602Y 
##############################
# AQM1602 # Pico # GPIO
##############################
#     +V  #  5   # GP3
#    SDA  #  6   # GP4
#    SCL  #  7   # GP5
#    GND  #  8   # GND
##############################

###############################################################################
# 参考文献1 LCD用I2C制御サンプル
# https://github.com/bokunimowakaru/RaspberryPi/blob/master/libs/soft_i2c.c
# Copyright (c) 2014-2017 Wataru KUNINO https://bokunimo.net/raspi/
'''
lcd_i2c.writeto_mem(aqm1602, 0x00, b'\x39') # LCD制御 IS=1
lcd_i2c.writeto_mem(aqm1602, 0x00, b'\x14') # LCD制御 OSC=4
lcd_i2c.writeto_mem(aqm1602, 0x00, b'\x73') # LCD制御 コントラスト  0x3
lcd_i2c.writeto_mem(aqm1602, 0x00, b'\x5E') # LCD制御 Power/Cont    0xE
lcd_i2c.writeto_mem(aqm1602, 0x00, b'\x6C') # LCD制御 FollowerCtrl  0xC
sleep(0.2);
lcd_i2c.writeto_mem(aqm1602, 0x00, b'\x38') # LCD制御 IS=0
lcd_i2c.writeto_mem(aqm1602, 0x00, b'\x0C') # LCD制御 DisplayON     0xC
'''

###############################################################################
# 参考文献2 Sitronix LCDコントローラST7032 データシート (2008/08/18)
# https://akizukidenshi.com/download/ds/sitronix/st7032.pdf

###############################################################################
# 参考文献3 レベルメータ用フォント作成 0x00～0x02:点灯数
# https://github.com/bokunimowakaru/xbeeCoord/tree/master/xbee_arduino/XBee_Coord/examples/sample11_lcd
# Copyright (c) 2013 Wataru KUNINO https://bokunimo.net/xbee/

###############################################################################
# Raspberry Pi Picoの消費電流
#  47 mA AQM1602Y-NLW-FBW(白色バックライト) バックライト 3.3V直ON
#  22 mA バックライトOFF
