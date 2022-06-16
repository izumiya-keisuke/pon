import algorithm
import math
import random
import sequtils

import myUtil
import puyopuyo
import nazopuyo
import solver

proc choiceColors(numColors: int): seq[Puyo]{.inline.} =
  ##[
    赤・緑・青・黄・紫の中から、指定された数の色をランダムに選ぶ

    Args:
      numColors (int): 色の数

    Returns:
      seq[Puyo]: RED・GREEN・BLUE・YELLOW・PURPLEからなる動的配列

    Examples:
      >>> let colors = choiceColors 3
      >>> assert colors == @[BLUE, PURPLE, RED]

    Note:
      numColorsは1〜5に入ることを前提としており、条件チェックを行っていない
  ]##
  return (RED..PURPLE).myChoice numColors

proc determinePuyoNum(nazo: Nazopuyo, fieldPuyoNum: int, colors: seq[Puyo],
    maxGarbageNum: int): array[RED..GARBAGE, int] =
  ##[
    使用するぷよの数を色ごとに決定する（お邪魔ぷよも）

    Args:
      nazo (Nazopuyo): 条件が設定されたなぞぷよ
      fieldPuyoNum (int): フィールドのぷよ数
      colors (seq[Puyo]): 使う色の動的配列
      maxGarbageNum (int): お邪魔ぷよの最大個数

    Returns:
      array[RED..GARBAGE, int]: 各ぷよを使う個数の配列

    Raises:
      ValueError: 対応していない条件が指定された時に発生

    Examples:
      >>> var nazo: Nazopuyo
      >>> nazo.moveNum = 3
      >>> nazo.condition = (CHAIN, 5, NONE, 0)
      >>> assert nazo.determinePuyoNum(@[GREEN, PURPLE], 5) == [0, 12, 0, 0, 8, 2]
  ]##
  if nazo.condition.kind notin {POP, CHAIN, CHAIN_MORE, CHAIN_POP,
      CHAIN_MORE_POP}:
    raise newException(ValueError, "未対応")

  if nazo.condition.kind in ChainKind:
    # 条件連鎖分
    let puyoNum = myDistribute(nazo.condition.num, colors.len, false)
    for i, p in colors:
      result[p] = 4*puyoNum[i]

    # 余剰分
    var extraNum: seq[int]
    if nazo.condition.kind in ChainMoreKind: # n連鎖以上の時は、最低1連鎖多くできるようにする
      result[colors.sample].inc 4
      extraNum = myDistribute(nazo.condition.extra-4, colors.len, true)
    else:
      extraNum = myDistribute(nazo.condition.extra, colors.len, true)
    for i, p in colors:
      result[p].inc extraNum[i]
  else:
    let fieldAndMovesPuyoNum = fieldPuyoNum+2*nazo.moveNum
    if fieldAndMovesPuyoNum < 4*colors.len: # 使う色は全て4個以上必要
      return result
    let puyoNum = myDistribute(fieldAndMovesPuyoNum-4*colors.len, colors.len, true)
    for i, p in colors:
      result[p] = 4+puyoNum[i]

  if maxGarbageNum > 0:
    result[GARBAGE] = rand maxGarbageNum

proc determineHeight(fieldPuyoNum: int, useX: array[1..6, bool],
    heightUniformity: int): array[1..6, int] =
  ##[
    フィールドの各列の高さを決める

    Args:
      fieldPuyoNum (int): フィールドのぷよ数の合計
      useX (array[1..6, bool]): 使用する列
      heightUniformity (int): 高さの均一度

    Returns:
      array[1..6, int]: 各列の高さ

    Raises:
      ValueError: 指定条件でフィールドを作れないとき

    Note:
      あらゆる境界条件チェックを省いている
      randomize()を事前に呼んでおく必要がある
      0: 完全にランダム
      1: 高さが2段未満の列が2列以上ある
      2: 最高段と最低段の段数差がfloor(n/6)+1以下
      3: floor(n/6)-2段を敷き詰めて、残りはランダム
      4: floor(n/6)-1段を敷き詰めて、残りはランダム
      5: 可能な限り平らに
  ]##
  let useXNum = useX.count true
  for _ in 0..<100: # 一定回数作って作れなかったら例外を投げる
    case heightUniformity:
      of 0..2:
        var height = myDistribute(fieldPuyoNum, useXNum, true)
        while heightUniformity == 1 and (height.filterIt it < 2).len < 2:
          height = myDistribute(fieldPuyoNum, useXNum, true)
        while heightUniformity == 2 and height.max-height.min >
            fieldPuyoNum div useXNum+1:
          height = myDistribute(fieldPuyoNum, useXNum, true)

        var idx = 0
        for x in 1..6:
          if useX[x]:
            result[x] = height[idx]
            idx.inc
      else:
        let tmp = max(fieldPuyoNum div useXNum-(5-heightUniformity), 0)
        for x in 1..6:
          if useX[x]:
            result[x] = tmp
        let leftPuyoNum = fieldPuyoNum-tmp*useXNum
        if heightUniformity < 5:
          let additionalHeight = myDistribute(leftPuyoNum, useXNum, true)
          var idx = 0
          for x in 1..6:
            if useX[x]:
              result[x].inc additionalHeight[idx]
              idx.inc
        else:
          var
            useXInt = newSeq[int](useXNum)
            idx = 0
          for x in 1..6:
            if useX[x]:
              useXInt[idx] = x
              idx.inc

          for x in useXInt.myChoice leftPuyoNum:
            result[x].inc

    if result.allIt it <= 13:
      return

  raise newException(ValueError, "指定条件ではフィールドを作れない")

proc unsetFieldAndMoves(nazo: var Nazopuyo) =
  ##[
    なぞぷよのフィールドとツモ達を消去する

    Args:
      nazo (var Nazopuyo): なぞぷよ

    Returns:
      （なし）

    Note:
      現在の実装では、ツモ達（nazo.moves）の初期化は不要なので省いている
  ]##
  nazo.field.initialize
  nazo.puyoNum.fill 0

proc setFieldAndMoves(nazo: var Nazopuyo, fieldPuyoNum: int, colors: seq[Puyo],
    maxGarbageNum: int, allowDoubleLast: bool, useX: array[1..6, bool],
        heightUniformity: int): bool =
  ##[
    条件のみ設定したなぞぷよに、フィールドとツモ達を設定する

    Args:
      nazo (var Nazopuyo): 条件のみ設定したなぞぷよ
      fieldPuyoNum (int): フィールドのぷよ数
      colors (seq[Puyo]): 使う色の動的配列
      maxGarbageNum (int): お邪魔ぷよの最大個数
      allowDoubleLast (bool): ゾロ発火を許すかどうか
      useX (array[1..6, bool]): 使用する列
      heightUniformity (int): 高さの均一度

    Returns:
      bool: フィールドとツモ達の設定に成功したかどうか

    Examples:
      >>> var nazo: Nazopuyo
      >>> nazo.moveNum = 3
      >>> nazo.condition = (CHAIN, 5, NONE, 0)
      >>> discard nazo.setFieldAndPieces(@[RED, BLUE], 5, false)
  ]##
  # usePuyoを決める
  # 例：puyoNum[RED] == 3、puyoNum[BLUE] == 1ならusePuyo == @[RED, RED, BLUE, RED]など
  let puyoNum = nazo.determinePuyoNum(fieldPuyoNum, colors, maxGarbageNum)
  if puyoNum.sum == 0:
    return false

  let allNum = puyoNum.sum
  var usePuyo = newSeqOfCap[Puyo](allNum)
  for p, n in puyoNum:
    for _ in 0..<n:
      usePuyo.add p

  while true:
    nazo.unsetFieldAndMoves

    # 使うぷよをフィールド用とツモ用に分割する
    for i in 0..100: # 無限ループになりうるので一定回数で打ち切り
      if i == 100:
        return false

      usePuyo.shuffle
      if usePuyo[0..2*nazo.moveNum-1].anyIt it notin ColorPuyoIter:
        continue
      if not allowDoubleLast and usePuyo[2*nazo.moveNum-2] == usePuyo[
          2*nazo.moveNum-1]:
        continue

      for p in usePuyo:
        nazo.puyoNum[p].inc
      break

    # ツモを決める
    for i in 0..<nazo.moveNum:
      nazo.moves[i] = ([usePuyo[2*i], usePuyo[2*i+1]], (0, UP))

    # 各列の高さを決める
    let height = determineHeight(allNum-2*nazo.moveNum, useX, heightUniformity)

    # 高さの分だけusePuyoから取り出して埋めていく
    var i = 2*nazo.moveNum
    for x in 1..6:
      nazo.field.nextSetY[x] = height[x]+1
      if height[x] == 0:
        continue
      for y in 1..height[x]:
        nazo.field.main[y][x] = usePuyo[i]
        nazo.field.existPuyoNum[usePuyo[i]][x].inc
        i.inc

    # 初期状態で消えたりばたんきゅ〜したりする場合は再決定
    let popData = nazo.field.startChain
    if popData.chainNum == 0 and not popData.die:
      return true

proc generateNazopuyo*(nazo: Nazopuyo, fieldPuyoNum, numColors: int,
    colors: seq[Puyo], maxGarbageNum: int, allowDoubleLast: bool,
        useX: array[1..6, bool], heightUniformity: int): string =
  ##[
    なぞぷよを生成する

    Args:
      nazo (Nazopuyo): 条件のみ入ったなぞぷよ
      fieldPuyoNum (int): フィールドのぷよ数
      numColors (int): 使う色数
      colors (seq[Puyo]): 使う色の動的配列
      maxGarbageNum (int): お邪魔ぷよの最大数
      allowDoubleLast (bool): ゾロ発火を許すかどうか
      useX (array[1..6, bool]): 使用する列
      heightUniformity (int): 高さの均一度

    Returns:
      string: 生成されたなぞぷよの問題URLと解答URL（'|'区切り）

    Raises:
      ValueError: 対応していない条件が指定された時に発生

    Examples:
      >>> var nazo: Nazopuyo
      >>> nazo.moveNum = 3
      >>> nazo.condition = (CHAIN, 5, NONE, 0)
      >>> echo nazo.generateNazopuyo(2, @[], 7, false)
        （3手の2色飽和5連鎖問題で、お邪魔ぷよの数が7個以下のなぞぷよのURL）

    Note:
      numColorsとcolorsは、どちらかが設定されていればよい
  ]##
  if nazo.condition.kind notin SupportedKind:
    raise newException(ValueError, "未対応")

  var
    copyColors = if colors.len == 0: choiceColors numColors else: colors
    copyNazo = nazo
  copyColors.shuffle
  copyNazo.moves = newSeq[Move](copyNazo.moveNum)

  # randする準備
  var
    minNum = 0
    maxNum = 0
  if copyNazo.condition.extra > 0:
    let minimum = if copyNazo.condition.kind in ChainMoreKind: 4 else: 1
    minNum = max(copyNazo.condition.extra*3 div 4, minimum)
    maxNum = copyNazo.condition.extra
  elif fieldPuyoNum > 0:
    minNum = max(fieldPuyoNum*3 div 4, 1)
    maxNum = fieldPuyoNum
  var pdf = newSeq[int](maxNum-minNum+1)
  pdf[0] = 1
  for i in 1..maxNum-minNum:
    pdf[i] = 2*pdf[i-1]
  let cdf = pdf.cumsummed

  while true:
    # randが必要なものをrandする
    if copyNazo.condition.extra > 0:
      copyNazo.condition.extra = (minNum..maxNum).toSeq.sample cdf

    var randFieldPuyoNum = fieldPuyoNum
    if fieldPuyoNum > 0:
      randFieldPuyoNum = (minNum..maxNum).toSeq.sample cdf

    if copyNazo.setFieldAndMoves(randFieldPuyoNum, copyColors, maxGarbageNum,
        allowDoubleLast, useX, heightUniformity):
      let operations = copyNazo.solve
      if operations.len == 1 and operations[0].len == copyNazo.moveNum:
        copyNazo.setReverseOperations operations[0]
        let answerUrl = $copyNazo
        copyNazo.clearMoves
        result = $copyNazo & '|' & answerUrl
        return

proc generateSimultaneousNazopuyo*(nazos: openArray[Nazopuyo]): seq[
    SimultaneousNazopuyo] =
  ##[
    複数のなぞぷよから連立なぞぷよを生成する

    Args:
      nazos (openArray[Nazopuyo]): なぞぷよ達

    Returns:
      seq[SimultaneousNazopuyo]: 生成された連立なぞぷよ達

    Note:
      オリジナルのなぞぷよのツモ順は保存し、その条件下で全パターンを検索する
  ]##
  # オリジナルの順番を保つ条件で可能なツモ順を全て調べる
  var
    simultaneousNazo = nazos.toSimultaneousNazopuyo
    useNazoIdxes = newSeqOfCap[int](simultaneousNazo.moveNum)
  for nazoIdx in 0..<simultaneousNazo.nazoNum:
    for _ in 0..<nazos[nazoIdx].moveNum:
      useNazoIdxes.add nazoIdx

  while true:
    var usedNum = newSeq[int](simultaneousNazo.nazoNum)
    for moveIdx in 0..<simultaneousNazo.moveNum:
      let nazoIdx = useNazoIdxes[moveIdx]
      simultaneousNazo.moves[moveIdx] = (-1, nazos[nazoIdx].moves[usedNum[nazoIdx]])
      usedNum[nazoIdx].inc

    let solutions = simultaneousNazo.solve
    if solutions.len == 1:
      result.add simultaneousNazo

    # 次のツモ順
    if not useNazoIdxes.nextPermutation:
      break

