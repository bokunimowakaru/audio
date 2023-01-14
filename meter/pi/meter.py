#!/usr/bin/env python3
# coding: utf-8

# PyAudio のインストールが必要です
# https://pypi.org/project/PyAudio/
#
# sudo apt-get install libportaudio2 libportaudiocpp0 portaudio19-dev
# pip3 install pyaudio
# 参考文献：https://www.s-toki.net/it/raspi-import-error/
#
# 【こんなときは】
# レベルが表示されないとき： arecord -l でカード番号を確認し INPUT = None を変更
# レベルが小さいとき：amixer でマイク音量を上げる

import datetime
from time import sleep			# スリープ実行モジュールの取得
import pyaudio
from math import log10
import sys
sys.path.append('../../radio/pi')
import raspi_lcd

raspiLcd = raspi_lcd.RaspiLcd(ignoreError=True,x=16,reset=16)	# raspiLcdの生成

date=datetime.datetime.today()									# 日付を取得
print(date.strftime('%Y/%m/%d %H:%M:%S'), "Example for AQM1602A/Y/Grove ----------")
raspiLcd.print('Audio Peak Meter by bokunimo.net')
sleep(5)

CHUNK = 1024					# Frames per buffer サンプル数
FORMAT = pyaudio.paInt16		# Sampling size and format サンプリング形式
CHANNELS = 1					# Number of channels モノラル=1、ステレオ=2
RATE  = 44100					# Sampling rate サンプリング周波数(Hz)
ARECCARD = 0					# None uses default device. 入力カード番号

peakMode = 'power'				# 電力尖頭値=power,電圧尖頭値=voltage
if peakMode == 'power':
	dispAcRangeDb = 40			# レベルメータ表示範囲(dB)
elif peakMode == 'voltage':
	dispAcRangeDb = 32			# レベルメータ表示範囲(dB)
else:
	dispAcRangeDb = 80			# レベルメータ表示範囲(dB)

if CHANNELS < 0 or CHANNELS > 2:
	print('ERROR: range of CHANNELS',CHANNELS,)
	exit

BITS = 8
if FORMAT == pyaudio.paInt16:
	BITS = 16					# 現状、未対応

pyAudio = pyaudio.PyAudio() 	# Instantiate PyAudio and initialize PortAudio
stream = pyAudio.open(			# Open stream
	format = FORMAT,			# Sampling size and format. 
	channels = CHANNELS,		# Number of channels
	rate = RATE,				# Sampling rate
	input_device_index = ARECCARD, # Index of Input Device to use. None uses default.
	input = True,				# Specifies whether this is an input stream.
	frames_per_buffer = CHUNK	# Specifies the number of frames per buffer
)

def calc_volt2db(volt): 		# dB電圧を0～100の表示尺で応答する
	if(volt <= 0):
		return 0
	i = int((20 * log10(volt/100) + dispAcRangeDb)/dispAcRangeDb * 100)
	if i < 0:
		i = 0
	if i > 100:
		i = 100
	return i

peak_i = 0
peakLv = [0, 0]
peakDb = [0, 0]
vu_filter = [[],[]]

while stream.is_active():		# Wait for stream to finish
	vals = [[],[]]
	valSum = [0.0, 0.0]
	valDc = [0.0, 0.0]
	valAc = [0.0, 0.0]
	voltDc = [0.0, 0.0]
	voltAc = [0.0, 0.0]
	while stream.get_read_available() < CHUNK:
		sleep(1e-6)
	data = stream.read(CHUNK, exception_on_overflow=False)
	stream.stop_stream()
	i=0
	ib=0
	prev=0
	val=0
	for sample in data:
		if BITS == 16:
			ib=int(not ib)
			if ib:
				prev = sample
				continue
			val = sample * 256 + prev 	# for little Endian
			if val >= 32768:			# if a >= 2 ** (bytes * 8):
				val -= 65536			# a -= 2 ** (bytes * 8)
			val = float(val) / 65536.	# ±0.5 
		else:
			val = sample
			if val >= 128:
				val -= 256
			val = float(val) / 256.		# ±0.5 
		valSum[i] += val
		vals[i].append(val)			   	# ADCから値を取得して変数valに代入
		if CHANNELS == 2:
			i=int(not i)
		peak_i += 1
	# print('DEBUG sampling, length =',len(vals[0]),len(vals[1]))
	# print('DEBUG valSum =', valSum[0], valSum[1])
	# print('DEBUG vals[0][0:4] =', vals[0][0:4])
	# print('DEBUG vals[1][0:4] =', vals[1][0:4])
	level = list()
	for ch in range(CHANNELS):
		valDc[ch] = valSum[ch] / float(CHUNK)
		if peakMode == 'power': 					# 尖頭電力メータ
			acSum = 0
			for i in range(CHUNK):					# 区間エネルギー計算
				acSum += abs(vals[ch][i] - valDc[ch])
			valAc[ch] = acSum / float(CHUNK)		# サンプル数で除算しPowerに
		elif peakMode == 'voltage': 				# 尖頭電圧メータ
			acVpp = 0
			for i in range(CHUNK - 1): # ピーク演算（簡易ノイズフィルタ付）
				vpp = abs(vals[ch][i] + vals[ch][i+1] - 2 * valDc[ch])
				if vpp > acVpp:
					acVpp = vpp
			valAc[ch] = acVpp / 2 / 1.41421356
		voltDc[ch] = valDc[ch] * 100.				# 直流分ADC値を百分率(%)に変換
		voltAc[ch] = valAc[ch] * 100.				# 交流分ADC値を百分率(%)に変換
		if peak_i > 16:
			peakLv[ch] = voltAc[ch]
			if ch >= CHANNELS - 1:
				peak_i = 0
		if peakLv[ch] < voltAc[ch]:
			peakLv[ch] = voltAc[ch]
		level.append(calc_volt2db(voltAc[ch]))
		# print('AC(%)='+str(round(voltAc[ch])),'Peak(%)='+str(round(peakLv[ch])),'Lv='+str(level))
	raspiLcd.printBar(level)
	stream.start_stream()
stream.close()
pyAudio.terminate()
