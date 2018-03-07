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
    DEFINE VARIABLE cFileName  AS CHARACTER NO-UNDO.
    DEFINE VARIABLE cDirectory AS CHARACTER NO-UNDO.
    DEFINE VARIABLE cErrorFile AS CHARACTER NO-UNDO.
    
    cFileName = ENTRY(2,cParameters).
    cDirectory = ENTRY(3,cParameters).
    cErrorFile = cFileName + ".e".

    /*RUN prodict/load_seq.r
      (INPUT cFileName,
       INPUT cDirectory).*/
    DEFINE NEW SHARED STREAM s_err.
    DEFINE VARIABLE seqname   AS CHARACTER NO-UNDO.
    DEFINE VARIABLE seqnumber AS CHARACTER NO-UNDO.
    DEFINE VARIABLE seqvalue  AS INT64     NO-UNDO.

    INPUT FROM VALUE(cDirectory + "/" + cFileName).
    REPEAT:
      IMPORT seqnumber seqname seqvalue NO-ERROR.
      IF ERROR-STATUS:ERROR THEN DO:
        OUTPUT STREAM s_err TO VALUE(cDirectory + "/" + cErrorFile) APPEND.
        PUT STREAM s_err UNFORMATTED "Error loading value for " seqname ": "
            ERROR-STATUS:GET-MESSAGE(1) SKIP.
        OUTPUT STREAM s_err CLOSE.
      END.

      DYNAMIC-CURRENT-VALUE(seqname , ldbname(1)) = seqvalue NO-ERROR.
      IF ERROR-STATUS:ERROR THEN DO:
        OUTPUT STREAM s_err TO VALUE(cDirectory + "/" + cErrorFile) APPEND.
        PUT STREAM s_err UNFORMATTED "Error setting value for " seqname ": "
            ERROR-STATUS:GET-MESSAGE(1) SKIP.
        OUTPUT STREAM s_err CLOSE.
      END.

      MESSAGE SUBSTITUTE("Set sequence &1 to value &2", seqname, seqvalue).
    END.
    INPUT CLOSE.
  END.
  ELSE IF cAction = "LOAD_DATA" THEN DO:
    DEFINE VARIABLE cTables  AS CHARACTER NO-UNDO.
    DEFINE VARIABLE cDataDir AS CHARACTER NO-UNDO.

    cTables = ENTRY(2,cParameters).
    cDataDir = ENTRY(3,cParameters).

    /*RUN prodict/load_d.r
      (INPUT cTables,
       INPUT cDataDir).*/

    DEFINE VARIABLE cDataFilename  AS CHARACTER NO-UNDO.
    DEFINE VARIABLE cTableName AS CHARACTER  NO-UNDO.
    DEFINE STREAM importSteam.

    INPUT FROM OS-DIR(cDataDir).
    REPEAT:
      IMPORT cDataFilename.
      IF cDataFilename BEGINS "." THEN DO:
        NEXT.
      END.

      cTableName = SUBSTRING(cDataFilename, R-INDEX(cDataFilename, '/') + 1).
      cTableName = REPLACE(cTableName,".d","").

      DEFINE VARIABLE hRecordBuffer AS HANDLE NO-UNDO.
      DEFINE VARIABLE hFieldBuffer AS HANDLE NO-UNDO.
      DEFINE VARIABLE iConter AS INTEGER    NO-UNDO.
      DEFINE VARIABLE cRecord AS CHARACTER  NO-UNDO.
      DEFINE VARIABLE cDelimiter AS CHARACTER  NO-UNDO INITIAL ",".

      ASSIGN
          cDelimiter     = CHR(32). /* space */
      // CREATE TEMP-TABLE hDynamicTempTable.
      // hDynamicTempTable:CREATE-LIKE("customer").
      // hDynamicTempTable:TEMP-TABLE-PREPARE("hDynTTName").
      // hRecordBuffer = hDynamicTempTable:DEFAULT-BUFFER-HANDLE.
      CREATE BUFFER hRecordBuffer FOR TABLE cTableName.

      INPUT STREAM importSteam FROM cDataFilename.

      OuterRepeat:
      REPEAT:
        IMPORT STREAM importSteam UNFORMATTED cRecord.
          DO TRANSACTION:
            hRecordBuffer:BUFFER-CREATE().
            REPEAT iConter = 1 TO NUM-ENTRIES(cRecord, cDelimiter) ON ERROR UNDO, LEAVE OuterRepeat:
                ASSIGN
                    hFieldBuffer = hRecordBuffer:BUFFER-FIELD(iConter)
                    hFieldBuffer:BUFFER-VALUE = ENTRY(iConter, cRecord, cDelimiter).
            END.
        END.
      END.
    END.

    INPUT STREAM importSteam CLOSE.
  END.
  ELSE DO:
    MESSAGE "UNKNOWN ACTION!".
  END.
END.
QUIT.
