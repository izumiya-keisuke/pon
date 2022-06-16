import algorithm

type
  Puyo* = enum
    NONE,
    RED,
    GREEN,
    BLUE,
    YELLOW,
    PURPLE,
    GARBAGE,
    WALL,
    COLOR_PUYO

  Piece* = array[2, Puyo] # Piece[0]: 軸ぷよ

  Field* = tuple
    main: array[15, array[8, Puyo]] # [0][x]・[y][0]・[y][7]: WALL
    nextSetY: array[1..6, int]
    existPuyoNum: array[RED..GARBAGE, array[1..6, int]]

  PlayerWindow* = tuple
    field: Field
    pieces: seq[Piece]
    visiblePiecesNum: int

  PopData* = tuple
    popNum: array[RED..GARBAGE, int]
    chainNum: int
    die: bool

  Direction* = enum
    UP,
    RIGHT,
    DOWN,
    LEFT

  Operation* = tuple
    fixedPuyoX: int
    direction: Direction

const
  FieldInitializer = [WALL, NONE, NONE, NONE, NONE, NONE, NONE, WALL]
  ExistPuyoNumInitializer = [0, 0, 0, 0, 0, 0]
  CheckedInitializer = [true, false, false, false, false, false, false, true]
  ColorPuyoIter* = RED..PURPLE
  PuyoIter* = RED..GARBAGE

proc isDouble*(piece: Piece): bool {.inline.} = piece[0] == piece[1]

proc print*(field: Field) =
  ##[
    フィールドを表示

    Args:
      field (Field): フィールド

    Returns:
      （なし）
  ]##
  for y in countdown(13, 1):
    var line = "|"
    for x in 1..6:
      line.add if field.main[y][x] == NONE: ' ' else: ($field.main[y][x])[0]
    line.add '|'

    echo line

  echo "--------"

proc initialize*(field: var Field) =
  ##[
    フィールドを初期化

    Args:
      field (var Field): フィールド

    Returns:
      （なし）
  ]##
  field.main.fill FieldInitializer
  field.main[0].fill WALL
  field.nextSetY.fill 1
  field.existPuyoNum.fill ExistPuyoNumInitializer

proc checkConnection(field: Field, y, x: int, checked: var array[14, array[8,
    bool]], connectPoint, connectGarbage: var seq[(int, int)]): int =
  ##[
    くっついているぷよを調べる

    Args:
      field (Field): フィールド
      y, x (int): 注目する位置
      checked (var array[14, array[8, bool]]): その位置をみたかどうか
      connectPoint (var seq[(int, int)]): くっついているぷよ達の位置の動的配列
      connectGarbage (var seq[(int, int)]): 隣接して消えうるお邪魔ぷよ達の位置の動的配列

    Returns:
      int: くっついているぷよ数

    Note:
      再帰関数になっているので、最初呼ぶときはconnectPointとconnectGarbageは長さ0にしておく
      壁が入っている部分の位置のcheckedはtrueにしておく
  ]##
  checked[y][x] = true
  connectPoint.add (y, x)

  result = 1
  for (Y, X) in [(y, x+1), (y, x-1), (y+1, x), (y-1, x)]:
    if checked[Y][X]:
      continue

    if field.main[Y][X] == field.main[y][x]:
      result.inc field.checkConnection(Y, X, checked, connectPoint, connectGarbage)
    elif field.main[Y][X] == GARBAGE:
      checked[Y][X] = true
      connectGarbage.add (Y, X)

proc startChain*(field: var Field): PopData =
  ##[
    連鎖をスタートさせる

    Args:
      field (var Field): フィールド（連鎖開始前）

    Returns:
      PopData: 連鎖が終わって得られた結果
  ]##
  result.popNum.fill 0
  result.chainNum = 0
  result.die = false

  while true:
    var
      anyPop = false
      checked: array[14, array[8, bool]]
    checked.fill CheckedInitializer
    checked[0].fill true
    checked[13].fill true

    for y in 1..12:
      for x in 1..6:
        if field.main[y][x] notin ColorPuyoIter or checked[y][x]:
          continue

        # ぷよの連結をチェックする
        var
          connectPoint: seq[(int, int)]
          connectGarbage: seq[(int, int)]
        let connectNum = field.checkConnection(y, x, checked, connectPoint, connectGarbage)
        if connectNum < 4:
          for (y, x) in connectGarbage:
            checked[y][x] = false
          continue

        # 4個以上つながっていたら消す
        anyPop = true
        result.popNum[field.main[y][x]].inc connectNum
        for (Y, X) in connectPoint:
          field.existPuyoNum[field.main[Y][X]][X].dec
          field.main[Y][X] = NONE
        for (Y, X) in connectGarbage:
          field.existPuyoNum[GARBAGE][X].dec
          field.main[Y][X] = NONE

    # ぷよを落とす
    if not anyPop:
      break

    result.chainNum.inc

    for x in 1..6:
      var leftPuyo: seq[Puyo]
      for y in 1..13:
        if field.main[y][x] != NONE and field.main[y][x] != WALL:
          leftPuyo.add field.main[y][x]

      let leftNum = leftPuyo.len
      field.nextSetY[x] = leftNum+1
      if leftNum == 13:
        continue

      for y in 1..leftNum:
        field.main[y][x] = leftPuyo[y-1]
      for y in leftNum+1..13:
        field.main[y][x] = NONE

  result.die = (field.main[12][3] != NONE)

proc fallPiece(field: var Field, piece: Piece, operation: Operation) =
  ##[
    ぷよ（ツモ）を置く

    Args:
      field (var Field): フィールド
      piece (Piece): ツモ
      operation (Operation): ツモを置く位置

    Returns:
      （なし）

    Raises:
      ValueError: 置けない位置に置こうとした時に発生

    Note:
      回しは考慮していない（実装予定）
  ]##
  let x = operation.fixedPuyoX
  let y = field.nextSetY[x]

  if (x == 1 and operation.direction == LEFT) or (x == 6 and
      operation.direction == RIGHT):
    raise newException(ValueError, "不可能な動作")

  case operation.direction
  of DOWN:
    field.main[y][x] = piece[1]
    field.main[y+1][x] = piece[0]

    field.nextSetY[x].inc 2
    field.existPuyoNum[piece[0]][x].inc
    field.existPuyoNum[piece[1]][x].inc
  else:
    field.main[y][x] = piece[0]
    field.existPuyoNum[piece[0]][x].inc

    case operation.direction
    of UP:
      field.main[y+1][x] = piece[1]

      field.nextSetY[x].inc 2
      field.existPuyoNum[piece[1]][x].inc
    of LEFT:
      field.main[field.nextSetY[x-1]][x-1] = piece[1]

      field.nextSetY[x-1].inc
      field.nextSetY[x].inc
      field.existPuyoNum[piece[1]][x-1].inc
    of RIGHT:
      field.main[field.nextSetY[x+1]][x+1] = piece[1]

      field.nextSetY[x+1].inc
      field.nextSetY[x].inc
      field.existPuyoNum[piece[1]][x+1].inc
    of DOWN:
      discard

  # 14段目のぷよを消す
  for X in 1..6:
    if field.nextSetY[X] == 15:
      field.existPuyoNum[field.main[14][X]][X].dec
      field.main[14][X] = NONE
      field.nextSetY[X].dec

proc operatePiece*(field: var Field, piece: Piece,
    operation: Operation): PopData =
  ##[
    1手（ぷよ（ツモ）を置き、連鎖スタート）進める

    Args:
      field (var Field): フィールド
      piece (Piece): ツモ
      operation (Operation): ツモを置く位置

    Returns:
      PopData: 連鎖が終わって得られた結果
  ]##
  field.fallPiece(piece, operation)
  return field.startChain
