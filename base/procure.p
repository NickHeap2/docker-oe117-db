DEFINE VARIABLE cParameters AS CHARACTER NO-UNDO.
DEFINE VARIABLE cAction     AS CHARACTER NO-UNDO.

cParameters = SESSION:PARAMETER.
/* do we have an action? */
IF cParameters <> "" THEN DO:
  cAction  = ENTRY(1,cParameters).

  IF cAction = "LOAD_SCHEMA" THEN DO:
    DEFINE VARIABLE cSchemaFile AS CHARACTER NO-UNDO.

    cSchemaFile = ENTRY(2,cParameters).

    RUN prodict/load_df.r
      (INPUT cSchemaFile).
  END.
  ELSE IF cAction = "LOAD_SEQUENCE_VALUES" THEN DO:
    DEFINE VARIABLE cFileName   AS CHARACTER NO-UNDO.
    DEFINE VARIABLE cDirectory AS CHARACTER NO-UNDO.

    cFileName = ENTRY(2,cParameters).
    cDirectory = ENTRY(3,cParameters).

    RUN prodict/load_seq.r
      (INPUT cFileName,
       INPUT cDirectory).
  END.
  ELSE IF cAction = "LOAD_DATA" THEN DO:
    DEFINE VARIABLE cTables  AS CHARACTER NO-UNDO.
    DEFINE VARIABLE cDataDir AS CHARACTER NO-UNDO.

    cTables = ENTRY(2,cParameters).
    cDataDir = ENTRY(3,cParameters).

    RUN prodict/load_d.r
      (INPUT cTables,
       INPUT cDataDir).
  END.
  ELSE DO:
    MESSAGE "UNKNOWN ACTION!".
  END.
END.
QUIT.
