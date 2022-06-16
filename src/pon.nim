import algorithm
import browsers
import sequtils
import strutils
import threadpool

import nimx/button
import nimx/editor/tab_view
import nimx/linear_layout
import nimx/popup_button
import nimx/table_view
import nimx/text_field
import nimx/scroll_view
import nimx/segmented_control
import nimx/timer
import nimx/view
import nimx/window

import generator
import myUtil
import nazopuyo
import puyopuyo
import random
import solver

type
  GenerateResultView = View
  SimultaneousResultView = View
  NumFieldView = View

const IsMobile = defined(ios) or defined(android)

proc newChangeNumButton(r: Rect, textField: TextField, diff: int): Button{.inline.} =
  ##[
    テキストフィールド内の数値を変えるボタンを生成する

    Args:
      r (Rect): 基となるrect
      textField (TextField): 変更する対象のテキストフィールド
      diff (int): 変更する値（負も可）

    Returns:
      Button: 生成したボタン

    Note:
      テキストフィールド内が整数値ではなかった場合、特に変更しない
      タイトルは、変更値dが非負なら「+d」、負なら「-d」となる
  ]##
  result = r.newButton
  result.title = if diff >= 0: "+" & $diff else: $diff
  result.onAction do():
    let (success, num) = textField.text.safeParseInt
    if success:
      textField.text = $(num+diff)

proc newUrlButton(r: Rect, title, url: string): Button{.inline.} =
  ##[
    URLをブラウザで開くボタンを生成する

    Args:
      r (Rect): 基となるrect
      title (string): 生成するボタンに表示する文字列
      url (string): ブラウザで開くURL

    Returns:
      Button: 生成したボタン
  ]##
  result = r.newButton
  result.title = title
  result.onAction do():
    url.openDefaultBrowser

proc newNumFieldView(x, y: Coord, dflt: int): NumFieldView =
  ##[
    数値変更ボタン付きの数値入力テキストフィールドを表すビューを生成する

    Args:
      x (Coord): ビューの左端
      y (Coord): ビューの上端
      dflt (int): テキストフィールドに最初入れておく値

    Returns:
      NumFieldView: 生成したビュー

    Note:
      result.subviews[0]がtextFieldの値（string）
  ]##
  result = newRect(x, y, 150, 20).newView
  let textField = newRect(60, 0, 30, 20).newTextField
  textField.text = $dflt
  let minus5Button = newRect(0, 0, 25, 20).newChangeNumButton(textField, -5)
  let minus1Button = newRect(30, 0, 25, 20).newChangeNumButton(textField, -1)
  let plus1Button = newRect(95, 0, 25, 20).newChangeNumButton(textField, +1)
  let plus5Button = newRect(125, 0, 25, 20).newChangeNumButton(textField, +5)
  result.addSubview textField
  result.addSubview minus5Button
  result.addSubview minus1Button
  result.addSubview plus1Button
  result.addSubview plus5Button

proc getNum(v: NumFieldView): int{.inline.} =
  ##[
    NumFieldViewの中のテキストフィールドに入っている数値を取り出す

    Args:
      v (NumFieldView): ビュー

    Returns:
      int: テキストフィールド内の数値
  ]##
  return (TextField)(v.subviews[0]).text.parseInt

proc newGenerateResultView(r: Rect, question,
    answer: string): GenerateResultView{.inline.} =
  ##[
    なぞぷよ生成結果を表すビューを生成する

    Args:
      r (Rect): 基となるrect
      question (string): 問題URL
      answer (string): 解答URL

    Returns:
      GenerateResultView: 生成したビュー
  ]##
  result = r.newView
  result.addSubview newRect(5, 5, 90, 20).newUrlButton("問題を開く", question)
  result.addSubview newRect(100, 5, 90, 20).newUrlButton("解を開く", answer)

proc setNewGenerateResultView(resultView: View, idx: int, question,
    answer: string){.inline.} =
  ##[
    なぞぷよ生成結果を表すビューを出力ビューにセットする

    Args:
      resultView (View): 出力ビュー
      idx (int): 生成したなぞぷよの通し番号
      question (string): 問題URL
      answer (string): 解答URL

    Returns:
      （なし）
  ]##
  resultView.addSubview newRect(0, (30*idx).Coord, resultView.frame.width,
      20).newGenerateResultView(question, answer)

proc setNewSolveResultView(resultView: View, nazo: Nazopuyo, solutions: openArray[Solution]) =
  ##[
    なぞぷよ解探索結果を表すビューを出力ビューにセットする

    Args:
      resultView (View): 出力ビュー
      solutions (openArray[Solution]): 解達（逆順）

    Returns:
      （なし）
  ]##
  for i, s in solutions:
    var copyNazo = nazo
    copyNazo.setReverseOperations s
    resultView.addSubview newRect(5, (5+30*i).Coord, 85, 20).newUrlButton("解を開く", $copyNazo)

proc setNewSimultaneousResultView(resultView: View, idx: int,
    simultaneousNazo: SimultaneousNazopuyo, solution: SimultaneousSolution){.inline.} =
  ##[
    連立なぞぷよツモ探索結果を表すビューを出力ビューにセットする

    Args:
      resultView (View): 出力ビュー
      idx (int): 解の通し番号
      simultaneousNazo (SimultaneousNazopuyo): 連立なぞぷよ
      solution (SimultaneousSolution): 解

    Returns:
      （なし）
  ]##
  let label = newRect(5, 5+25*idx.Coord, 150, 20).newLabel
  resultView.addSubview label

  var nazo: Nazopuyo
  nazo.field.initialize
  nazo.condition = (NO_CONDITION, 0, NONE, 0)
  nazo.moveNum = simultaneousNazo.moveNum
  nazo.moves = newSeq[Move](nazo.moveNum)
  for i in 0..<nazo.moveNum:
    nazo.moves[i] = simultaneousNazo.moves[i][1]

  resultView.addSubview newRect(5, 5+30*idx.Coord, 85, 20).newUrlButton(
      "ツモを開く", $nazo)

proc writeToFile(urls: (string, string), fileName: string){.inline.} =
  ##[
    問題URLと解答URLをタブ区切り、改行付きでファイルに追記する

    Args:
      urls (string, string): 問題URL、解答URL
      fileName (string): 書き込むファイル名

    Returns:
      （なし）
  ]##
  let f = fileName.open FileMode.fmAppend
  defer: f.close
  f.writeLine urls[0] & '\t' & urls[1]

proc setNewGeneratorView(mainWindow: Window) =
  ##[
    なぞぷよ生成ビューを生成し、メインウィンドウにセットする

    Args:
      mainWindow (Window): メインウィンドウ

    Returns:
      （なし）
  ]##
  let generatorView = mainWindow.subviews[0].subviews[0].frame.newView
  (TabView)(mainWindow.subviews[0].subviews[0]).addTab("なぞぷよ生成", generatorView)

  # クリア条件入力
  let clearConditionLabel = newRect(10, 10, 80, 20).newLabel
  clearConditionLabel.text = "クリア条件"
  let clearConditionPopupButton = PopupButton.new newRect(10, 30, 250, 20)
  clearConditionPopupButton.items = ["cぷよ全て消すべし",
      "n連鎖すべし", "n連鎖以上すべし",
      "n連鎖＆cぷよ全て消すべし", "n連鎖以上＆cぷよ全て消すべし"]
  generatorView.addSubview clearConditionLabel
  generatorView.addSubview clearConditionPopupButton

  # nの値入力
  let nInputLabel = newRect(270, 10, 50, 20).newLabel
  nInputLabel.text = "n ="
  let nInputNumFieldView = newNumFieldView(270, 30, 1)
  generatorView.addSubview nInputLabel
  generatorView.addSubview nInputNumFieldView

  # cの色入力
  let cInputLabel = newRect(430, 10, 50, 20).newLabel
  cInputLabel.text = "c ="
  let cInputPopupButton = PopupButton.new newRect(430, 30, 80, 20)
  cInputPopupButton.items = ["全", "赤", "緑", "青", "黄", "紫",
      "お邪魔", "色"]
  generatorView.addSubview cInputLabel
  generatorView.addSubview cInputPopupButton

  # 手数入力
  let moveNumInputLabel = newRect(520, 10, 50, 20).newLabel
  moveNumInputLabel.text = "手数"
  let moveNumFieldView = newNumFieldView(520, 30, 1)
  generatorView.addSubview moveNumInputLabel
  generatorView.addSubview moveNumFieldView

  # 余剰ぷよ最大数入力
  let extraInputLabel = newRect(10, 70, 120, 20).newLabel
  extraInputLabel.text = "余剰ぷよ最大数"
  let extraNumFieldView = newNumFieldView(10, 90, 0)
  generatorView.addSubview extraInputLabel
  generatorView.addSubview extraNumFieldView

  # フィールド色ぷよ最大数入力
  let fieldInputLabel = newRect(180, 70, 170, 20).newLabel
  fieldInputLabel.text = "フィールド色ぷよ最大数"
  let fieldNumFieldView = newNumFieldView(180, 90, 0)
  generatorView.addSubview fieldInputLabel
  generatorView.addSubview fieldNumFieldView

  # お邪魔ぷよ最大数入力
  let garbageInputLabel = newRect(365, 70, 140, 20).newLabel
  garbageInputLabel.text = "お邪魔ぷよ最大数"
  let garbageNumFieldView = newNumFieldView(365, 90, 0)
  generatorView.addSubview garbageInputLabel
  generatorView.addSubview garbageNumFieldView

  # 高さ均一度入力
  let uniformNumLabel = newRect(530, 70, 80, 20).newLabel
  uniformNumLabel.text = "高さ均一度"
  let uniformNumPopupButton = PopupButton.new newRect(530, 90, 50, 20)
  uniformNumPopupButton.items = (0..5).toSeq.mapIt $it
  generatorView.addSubview uniformNumLabel
  generatorView.addSubview uniformNumPopupButton

  # ゾロ発火の有無を選択
  let allowDoubleLastLabel = newRect(620, 70, 80, 20).newLabel
  allowDoubleLastLabel.text = "ゾロ発火"
  let allowDoubleLastSegmentedControl = SegmentedControl.new newRect(620, 90, 80, 20)
  allowDoubleLastSegmentedControl.segments = @["禁止", "許可"]
  generatorView.addSubview allowDoubleLastLabel
  generatorView.addSubview allowDoubleLastSegmentedControl

  # 使用する列を選択
  let emptyXLabel = newRect(10, 130, 120, 20).newLabel
  emptyXLabel.text = "使用する列"
  generatorView.addSubview emptyXLabel
  var emptyEachXLabel: array[1..6, TextField]
  var emptyXSegmentedControl: array[1..6, SegmentedControl]
  for x in 1..6:
    emptyEachXLabel[x] = newRect((10+110*(x-1)).Coord, 150, 80, 20).newLabel
    emptyEachXLabel[x].text = $x & "列目"
    emptyXSegmentedControl[x] = SegmentedControl.new newRect((10+110*(
        x-1)).Coord, 170, 100, 20)
    emptyXSegmentedControl[x].segments = @["使用", "未使用"]
    generatorView.addSubview emptyEachXLabel[x]
    generatorView.addSubview emptyXSegmentedControl[x]

  # 色の決め方を選択
  let selectColorKindLabel = newRect(10, 210, 120, 20).newLabel
  selectColorKindLabel.text = "色の決め方"
  let selectColorKindSegmentedControl = SegmentedControl.new newRect(10, 230, 140, 20)
  selectColorKindSegmentedControl.segments = @["色数指定", "色指定"]
  generatorView.addSubview selectColorKindLabel
  generatorView.addSubview selectColorKindSegmentedControl

  # 色数を選択
  let selectColorNumView = newRect(160, 210, 540, 40).newView
  let selectColorNumLabel = newRect(0, 0, 50, 20).newLabel
  selectColorNumLabel.text = "色数"
  let selectColorNumPopupButton = PopupButton.new newRect(0, 20, 50, 20)
  selectColorNumPopupButton.items = (1..5).toSeq.mapIt $it
  selectColorNumView.addSubview selectColorNumLabel
  selectColorNumView.addSubview selectColorNumPopupButton
  generatorView.addSubview selectColorNumView

  # 色を選択
  let selectColorView = newRect(160, 210, 540, 40).newView
  const colorName = ["赤", "緑", "青", "黄", "紫"]
  var selectColorLabel: array[5, TextField]
  var selectColorSegmentedControl: array[5, SegmentedControl]
  for c in 0..<5:
    selectColorLabel[c] = newRect((110*c).Coord, 0, 40, 20).newLabel
    selectColorLabel[c].text = colorName[c]
    selectColorSegmentedControl[c] = SegmentedControl.new newRect((110*c).Coord,
        20, 100, 20)
    selectColorSegmentedControl[c].segments = @["使用", "未使用"]
    selectColorSegmentedControl[c].selectedSegment = 1
    selectColorView.addSubview selectColorLabel[c]
    selectColorView.addSubview selectColorSegmentedControl[c]
  selectColorView.hidden = true
  generatorView.addSubview selectColorView

  # 色を選ぶ方法を切り替えたときのアクション
  selectColorKindSegmentedControl.onAction do():
    case selectColorKindSegmentedControl.selectedSegment
    of 0: # 色数指定
      selectColorView.hidden = true
      selectColorNumView.hidden = false
    of 1: # 色指定
      selectColorNumView.hidden = true
      selectColorView.hidden = false
    else:
      discard

  # URL形式を選択
  let urlFormatLabel = newRect(10, 270, 80, 20).newLabel
  urlFormatLabel.text = "URL形式"
  let urlFormatPopupButton = PopupButton.new newRect(10, 290, 160, 20)
  urlFormatPopupButton.items = ["ishikawapuyo.net", "ips.karou.jp"]
  generatorView.addSubview urlFormatLabel
  generatorView.addSubview urlFormatPopupButton

  # 並列処理数を入力
  let parallelInputLabel = newRect(180, 270, 90, 20).newLabel
  parallelInputLabel.text = "並列処理数"
  let parallelNumFieldView = newNumFieldView(180, 290, 1)
  generatorView.addSubview parallelInputLabel
  generatorView.addSubview parallelNumFieldView

  # 生成数を入力
  let generateNumInputLabel = newRect(340, 270, 50, 20).newLabel
  generateNumInputLabel.text = "生成数"
  let generateNumFieldView = newNumFieldView(340, 290, 1)
  generatorView.addSubview generateNumInputLabel
  generatorView.addSubview generateNumFieldView

  # 出力ファイル名を入力
  let outFileNameLabel = newRect(500, 270, 120, 20).newLabel
  outFileNameLabel.text = "出力ファイル名"
  let outFileNameTextField = newRect(500, 290, 150, 20).newTextField
  outFileNameTextField.text = "out.csv"
  generatorView.addSubview outFileNameLabel
  generatorView.addSubview outFileNameTextField

  # 生成ボタン
  var generating = false
  let generateButton = newRect(generatorView.frame.width/2-50, 350, 100, 100).newButton
  generateButton.title = "生成！"
  generatorView.addSubview generateButton

  generateButton.onAction do():
    if generating:
      return

    generating = true
    generateButton.title = "生成中…"
    var generatedNum = 0
    Mode = GENERATE
    mainWindow.subviews[0].subviews[1].removeAllSubviews
    mainWindow.drawWindow

    # 入力されているデータ達を読み込む
    var nazo: Nazopuyo
    case clearConditionPopupButton.selectedIndex
    of 0:
      nazo.condition.kind = POP
    of 1:
      nazo.condition.kind = CHAIN
    of 2:
      nazo.condition.kind = CHAIN_MORE
    of 3:
      nazo.condition.kind = CHAIN_POP
    of 4:
      nazo.condition.kind = CHAIN_MORE_POP
    else:
      discard
    nazo.condition.num = nInputNumFieldView.getNum
    case cInputPopupButton.selectedIndex
    of 7:
      nazo.condition.color = COLOR_PUYO
    else:
      nazo.condition.color = NONE.succ cInputPopupButton.selectedIndex
    nazo.moveNum = moveNumFieldView.getNum
    nazo.condition.extra = extraNumFieldView.getNum

    let fieldPuyoNum = fieldNumFieldView.getNum
    let maxGarbageNum = garbageNumFieldView.getNum
    let heightUniformity = uniformNumPopupButton.selectedIndex
    let allowDoubleLast = allowDoubleLastSegmentedControl.selectedSegment == 1

    var useX: array[1..6, bool]
    for x in 1..6:
      useX[x] = emptyXSegmentedControl[x].selectedSegment == 0
    var
      numColors = 0
      colors: seq[Puyo]
    if selectColorKindSegmentedControl.selectedSegment == 0:
      numColors = selectColorNumPopupButton.selectedIndex+1
    else:
      for i in 0..<5:
        if selectColorSegmentedControl[i].selectedSegment == 0:
          colors.add RED.succ i

    UseIpsFormat = urlFormatPopupButton.selectedIndex == 1
    let parallelNum = parallelNumFieldView.getNum
    let generateNum = generateNumFieldView.getNum
    let fileName = outFileNameTextField.text

    # 生成
    let maxNum = if generateNum == 0: int.high else: generateNum
    var
      nazoUrlFV = newSeq[FlowVar[string]](parallelNum)
      working = newSeq[bool](parallelNum) # 各スレッドが動いているかどうか

    for i in 0..<min(parallelNum, generateNum):
      nazoUrlFV[i] = spawn nazo.generateNazopuyo(fieldPuyoNum, numColors,
          colors, maxGarbageNum, allowDoubleLast, useX, heightUniformity)
      working[i] = true

    var t: Timer
    t = setInterval(1.0, proc() =
      for i in 0..<parallelNum:
        if not working[i] or not nazoUrlFV[i].isReady:
          continue

        let urls = (^nazoUrlFV[i]).split '|'
        working[i] = false
        mainWindow.subviews[0].subviews[1].setNewGenerateResultView(
            generatedNum, urls[0], urls[1])
        mainWindow.drawWindow
        (urls[0], urls[1]).writeToFile fileName

        generatedNum.inc
        if generatedNum+(working.count true) >= maxNum:
          continue
        nazoUrlFV[i] = spawn nazo.generateNazopuyo(fieldPuyoNum, numColors,
            colors, maxGarbageNum, allowDoubleLast, useX, heightUniformity)
        working[i] = true

      if working.allIt (not it):
        generating = false
        generateButton.title = "生成！"
        mainWindow.drawWindow
        t.clear
        return
    )

proc setNewSolveView(mainWindow: Window) =
  ##[
    なぞぷよ解探索ビューを生成し、メインウィンドウにセットする

    Args:
      mainWindow (Window): メインウィンドウ

    Returns:
      （なし）
  ]##
  let solveView = mainWindow.subviews[0].subviews[0].frame.newView
  (TabView)(mainWindow.subviews[0].subviews[0]).addTab("なぞぷよ解探索", solveView)

  # 問題のURLを入力
  let urlLabel = newRect(10, 10, 150, 20).newLabel
  urlLabel.text = "問題のURL"
  let urlTextField = newRect(10, 30, 600, 20).newTextField
  solveView.addSubview urlLabel
  solveView.addSubview urlTextField

  # 探索ボタン
  var solving = false
  let solveButton = newRect(650, 50, 100, 100).newButton
  solveButton.title = "解探索！"
  solveView.addSubview solveButton

  solveButton.onAction do():
    if solving:
      return

    solving = true
    solveButton.title = "探索中…"
    Mode = SOLVER
    mainWindow.subviews[0].subviews[1].removeAllSubviews
    mainWindow.drawWindow

    # 入力データ読取
    let nazo = urlTextField.text.toNazopuyo

    # 探索
    var solutionsFV = spawn nazo.solve

    var t: Timer
    t = setInterval(1.0, proc() =
      if not solutionsFV.isReady:
        return

      let solutions = (^solutionsFV)
      mainWindow.subviews[0].subviews[1].setNewSolveResultView(
          nazo, solutions)
      mainWindow.drawWindow

      solving = false
      solveButton.title = "解探索！"
      mainWindow.drawWindow
      t.clear
    )

proc setNewSimultaneousView(mainWindow: Window) =
  ##[
    連立なぞぷよビューを生成し、メインウィンドウにセットする

    Args:
      mainWindow (Window): メインウィンドウ

    Returns:
      （なし）
  ]##
  let simultaneousView = mainWindow.subviews[0].subviews[0].frame.newView
  (TabView)(mainWindow.subviews[0].subviews[0]).addTab("連立なぞぷよ", simultaneousView)

  # 1つめの問題のURLを入力
  let firstUrlLabel = newRect(10, 10, 150, 20).newLabel
  firstUrlLabel.text = "1つめの問題のURL"
  let firstUrlTextField = newRect(10, 30, 600, 20).newTextField
  simultaneousView.addSubview firstUrlLabel
  simultaneousView.addSubview firstUrlTextField

  # 2つめの問題のURLを入力
  let secondUrlLabel = newRect(10, 70, 150, 20).newLabel
  secondUrlLabel.text = "2つめの問題のURL"
  let secondUrlTextField = newRect(10, 90, 600, 20).newTextField
  simultaneousView.addSubview secondUrlLabel
  simultaneousView.addSubview secondUrlTextField

  # 並列処理数を入力
  let parallelInputLabel = newRect(10, 130, 90, 20).newLabel
  parallelInputLabel.text = "並列処理数"
  let parallelNumFieldView = newNumFieldView(10, 150, 1)
  simultaneousView.addSubview parallelInputLabel
  simultaneousView.addSubview parallelNumFieldView

  # 生成ボタン
  var generating = false
  let generateButton = newRect(650, 50, 100, 100).newButton
  generateButton.title = "生成！"
  simultaneousView.addSubview generateButton

  generateButton.onAction do():
    if generating:
      return

    generating = true
    generateButton.title = "生成中…"
    Mode = GENERATE
    mainWindow.subviews[0].subviews[1].removeAllSubviews
    mainWindow.drawWindow

    # 入力データ読取
    var nazos = newSeq[Nazopuyo](2)
    nazos[0] = firstUrlTextField.text.toNazopuyo
    nazos[1] = secondUrlTextField.text.toNazopuyo
    let parallelNum = parallelNumFieldView.getNum

    # オリジナルの順番を保つ条件で可能なツモ順を全て調べる
    var
      simultaneousNazo = nazos.toSimultaneousNazopuyo
      useNazoIdxes = newSeqOfCap[int](simultaneousNazo.moveNum)
    for nazoIdx in 0..<simultaneousNazo.nazoNum:
      for _ in 0..<nazos[nazoIdx].moveNum:
        useNazoIdxes.add nazoIdx

    # 生成
    var
      solutionsFV = newSeq[FlowVar[seq[SimultaneousSolution]]](parallelNum)
      generatingNazo = newSeq[SimultaneousNazopuyo](
          parallelNum) # 各スレッドで扱っているなぞぷよ
      working = newSeq[bool](parallelNum) # 各スレッドが動いているかどうか

    for i in 0..<parallelNum:
      simultaneousNazo.setMoves(nazos, useNazoIdxes)
      generatingNazo[i] = simultaneousNazo
      solutionsFV[i] = spawn simultaneousNazo.solve
      working[i] = true
      if not useNazoIdxes.nextPermutation:
        break

    var
      generatedNum = 0
      t: Timer
    t = setInterval(1.0, proc() =
      for i in 0..<parallelNum:
        if not working[i] or not solutionsFV[i].isReady:
          continue

        let solutions = ^solutionsFV[i]
        working[i] = false
        if solutions.len == 1:
          mainWindow.subviews[0].subviews[1].setNewSimultaneousResultView(
              generatedNum, simultaneousNazo, solutions[0])
          generatedNum.inc
          mainWindow.drawWindow

        simultaneousNazo.setMoves(nazos, useNazoIdxes)
        if not useNazoIdxes.nextPermutation:
          break

        generatingNazo[i] = simultaneousNazo
        working[i] = true
        solutionsFV[i] = spawn simultaneousNazo.solve

      if working.allIt (not it):
        generating = false
        generateButton.title = "生成！"
        mainWindow.drawWindow
        t.clear
        return
    )

proc startApp() =
  let mainWindow = when IsMobile: newFullscreenWindow() else: newRect(40, 40,
      1000, 600).newWindow
  mainWindow.title = "PON!"

  # 大元のスプリットビュー
  let splitView = mainWindow.bounds.newHorizontalLayout
  mainWindow.addSubview splitView

  # スプリットビューの左は入力ビュー、右は出力ビュー
  let mainView = TabView.new newRect(0, 0, 800, 600)
  let resultView = newRect(800, 0, 200, 600).newView
  splitView.addSubview mainView
  splitView.addSubview resultView

  mainWindow.setNewGeneratorView
  mainWindow.setNewSolveView
  mainWindow.setNewSimultaneousView

runApplication:
  randomize()
  startApp()
