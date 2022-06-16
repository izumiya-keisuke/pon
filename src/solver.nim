import math
import sequtils

import myUtil
import nazopuyo
import puyopuyo

type
  SolverMode* = enum
    GENERATE, # 生成モード（2つ以上の解が見つかったら打ち切り）
    SOLVER # 探索モード（全ての解を探索）

  Solution* = seq[Operation]
  SimultaneousSolution* = seq[(int, Operation)] # 対象のなぞぷよ番号、操作

var Mode* = GENERATE

const
  AllOperations: seq[Operation] = @[
      (1, UP), (1, RIGHT), (1, DOWN),
      (2, UP), (2, RIGHT), (2, DOWN), (2, LEFT),
      (3, UP), (3, RIGHT), (3, DOWN), (3, LEFT),
      (4, UP), (4, RIGHT), (4, DOWN), (4, LEFT),
      (5, UP), (5, RIGHT), (5, DOWN), (5, LEFT),
      (6, UP), (6, DOWN), (6, LEFT)
  ]
  # ゾロの場合は入れ替えた置き方は同じものとみなす
  AllDoubleOperations: seq[Operation] = @[
      (1, UP), (1, RIGHT), (2, UP), (2, RIGHT),
      (3, UP), (3, RIGHT), (4, UP), (4, RIGHT),
      (5, UP), (5, RIGHT), (6, UP)
  ]

proc solveRec(nazo: var Nazopuyo, nextIdx: int): seq[Solution] =
  ##[
    なぞぷよの解を探索する（再帰）

    Args:
      nazo (var Nazopuyo): なぞぷよ（探索途中状態）
      nextIdx (int): 次に置くぷよが何手目か（0-indexed）

    Returns:
      seq[Solution]: nazoをスタートとした際の解である操作列達（逆順）

    Note:
      nazoはvar変数だが、呼び出し前と呼び出し後で値が不変（実装・パフォーマンス上の理由）
      ModeがGENERATEの場合、2つ以上解を見つけた時点でそれらを返して終了
  ]##
  # 枝刈り
  if nazo.condition.kind in AllPopKind:
    # 消す対象の色で、4個未満しかない色がある場合
    case nazo.condition.color
    of NONE: # 全ぷよ消すべし
      if nazo.puyoNum[ColorPuyoIter].anyIt(0 < it and it < 4):
        return
    of RED..PURPLE:
      if 0 < nazo.puyoNum[nazo.condition.color] and nazo.puyoNum[
          nazo.condition.color] < 4:
        return
    else:
      discard

  if nazo.condition.kind in ChainKind:
    # フィールドとツモ全てを合わせても条件連鎖数に満たない場合
    if (nazo.puyoNum[ColorPuyoIter].mapIt it div 4).sum < nazo.condition.num:
      return

  # 枝刈り後の全探索
  let
    originalField = nazo.field
    operations = if nazo.moves[nextIdx].piece.isDouble:
      AllDoubleOperations else: AllOperations
  for op in operations:
    # 軸ぷよは14段目には置けない
    if nazo.field.nextSetY[op.fixedPuyoX] == 14:
      continue

    let popData = nazo.operatePiece(nextIdx, op)
    if nazo.clear popData:
      result.add @[op]
    elif popData.die:
      discard
    else:
      if nextIdx+1 < nazo.moveNum:
        var solutions = nazo.solveRec nextIdx+1
        let length = solutions.len
        for i in 0..<length:
          solutions[i].add op
        result &= solutions

    nazo.undo(originalField, popData)

    # 生成時は、2つ以上解を見つけたら打ち切り
    if Mode == GENERATE and result.len > 1:
      return

proc solve*(nazo: Nazopuyo): seq[Solution] =
  ##[
    なぞぷよの解を探索する

    Args:
      nazo (var Nazopuyo): なぞぷよ

    Returns:
      seq[Solution]: 解である操作列達（逆順）

    Raises:
      ValueError: 対応していない条件を指定すると発生

    Note:
      ModeがGENERATEの場合、2つ以上解を見つけた時点でそれらを返して終了
  ]##
  if nazo.condition.kind notin SupportedKind:
    raise newException(ValueError, "未対応")
  if nazo.moveNum < 1:
    return

  var copyNazo = nazo
  return copyNazo.solveRec 0

proc solveCore(simultaneousNazo: SimultaneousNazopuyo, targetNazoIdxes: seq[
    int]): seq[SimultaneousSolution] =
  ##[
    連立なぞぷよの解を探索する（どのなぞぷよに置くかを指定）

    Args:
      simultaneousNazo (SimultaneousNazopuyo): 連立なぞぷよ
      targetNazoIdxes (seq[int]): どのなぞぷよに置くかを表す動的配列

    Returns:
      seq[SimultaneousSolution]: 解達

    Note:
      ModeがGENERATEの場合、2つ以上解を見つけた時点でそれらを返して終了
  ]##
  var nazos = newSeq[Nazopuyo](simultaneousNazo.nazoNum)
  for nazoIdx in 0..<simultaneousNazo.nazoNum:
    nazos[nazoIdx].field = simultaneousNazo.fields[nazoIdx]
    nazos[nazoIdx].condition = simultaneousNazo.conditions[nazoIdx]
  for i, nazoIdx in targetNazoIdxes:
    nazos[nazoIdx].moveNum.inc
    nazos[nazoIdx].moves.add simultaneousNazo.moves[i][1]
  for nazoIdx in 0..<simultaneousNazo.nazoNum:
    nazos[nazoIdx].setPuyoNum

  var
    solutionsNum = 1
    solutionses = newSeq[seq[seq[Operation]]](
        simultaneousNazo.nazoNum) # 各なぞぷよの解達
  for i in 0..<simultaneousNazo.nazoNum:
    solutionses[i] = nazos[i].solve
    solutionsNum *= solutionses[i].len
    if solutionsNum == 0:
      break

  if solutionsNum > 1:
    return @[@[(0, (0, UP))], @[(0, (0, UP))]] # 複数解であることのみ通知（改善予定）
  elif solutionsNum == 1:
    var
      solution = newSeq[(int, Operation)](simultaneousNazo.moveNum)
      operatedNum = newSeq[int](simultaneousNazo.nazoNum) # 各なぞぷよで何回操作をしたか
    for moveIdx in 0..<simultaneousNazo.moveNum:
      let nazoIdx = targetNazoIdxes[moveIdx]
      for operation in solutionses[nazoIdx][0]:
        solution[moveIdx] = (nazoIdx, operation)
        operatedNum[nazoIdx].inc

    result.add solution

proc solve*(simultaneousNazo: SimultaneousNazopuyo): seq[
    SimultaneousSolution] =
  ##[
    連立なぞぷよの解を探索する

    Args:
      simultaneousNazo (SimultaneousNazopuyo): 連立なぞぷよ

    Returns:
      seq[SimultaneousSolution]: 解達

    Note:
      ModeがGENERATEの場合、2つ以上解を見つけた時点でそれらを返して終了
  ]##
  # どのなぞぷよに置くかの順番を全パターン列挙
  let targetNazoIdxeses = homoProduct(simultaneousNazo.nazoNum,
      simultaneousNazo.moveNum)

  for idxes in targetNazoIdxeses:
    result &= simultaneousNazo.solveCore idxes
    if result.len > 1:
      return
