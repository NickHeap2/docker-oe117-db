DEFINE VARIABLE cParameters AS CHARACTER NO-UNDO.
DEFINE VARIABLE cAction     AS CHARACTER NO-UNDO.

DEFINE STREAM importSteam.
DEFINE NEW SHARED STREAM s_err.

PAUSE 0 BEFORE-HIDE.

cParameters = SESSION:PARAMETER.
/* do we have an action? */
IF cParameters <> "" THEN DO:
  cAction = ENTRY(1,cParameters).

  IF cAction = "LOAD_SCHEMA" THEN DO:
    RUN LoadSchema IN THIS-PROCEDURE
      (ENTRY(2,cParameters)).
  END.
  ELSE IF cAction = "ADD_USER" THEN DO:
    RUN AddUser IN THIS-PROCEDURE
      (ENTRY(2,cParameters),
       ENTRY(3,cParameters),
       ENTRY(4,cParameters)).
  END.
  ELSE IF cAction = "LOAD_SEQUENCE_VALUES" THEN DO:
    RUN LoadSequenceValues IN THIS-PROCEDURE
      (ENTRY(2,cParameters),
       ENTRY(3,cParameters)).
  END.
  ELSE IF cAction = "EMPTY_DATA" THEN DO:
    RUN EmptyData IN THIS-PROCEDURE
      (REPLACE(ENTRY(2,cParameters), "|", ",")).
  END.
  ELSE IF cAction = "LOAD_DATA" THEN DO:
    RUN LoadData IN THIS-PROCEDURE
      (ENTRY(2,cParameters),
       ENTRY(3,cParameters)).
  END.
  ELSE DO:
    MESSAGE "UNKNOWN ACTION!".
  END.
END.
QUIT.

PROCEDURE AddUser:
  DEFINE INPUT PARAMETER cUserId AS CHARACTER NO-UNDO.
  DEFINE INPUT PARAMETER cUsername AS CHARACTER NO-UNDO.
  DEFINE INPUT PARAMETER cPassword AS CHARACTER NO-UNDO.

  DEFINE VARIABLE h_userBuffer AS HANDLE NO-UNDO.

  CREATE BUFFER h_userBuffer FOR TABLE SUBSTITUTE("&1.&2", LDBNAME(1), "_user") NO-ERROR.
  _TRANSACTION:
  DO TRANSACTION:
    h_userBuffer:BUFFER-CREATE().

    h_userBuffer:BUFFER-FIELD("_Userid"):BUFFER-VALUE() = cUserId.
    h_userBuffer:BUFFER-FIELD("_User-Name"):BUFFER-VALUE() = cUsername.
    h_userBuffer:BUFFER-FIELD("_Password"):BUFFER-VALUE() = ENCODE(cPassword).

    h_userBuffer:BUFFER-RELEASE().
  END.
END PROCEDURE.

PROCEDURE EmptyData:
  DEFINE INPUT PARAMETER emptyTables AS CHARACTER NO-UNDO.

  DEFINE VARIABLE thisTable AS CHARACTER NO-UNDO.
  DEFINE VARIABLE currentMessage AS INTEGER NO-UNDO.
  DEFINE VARIABLE errorMessage AS CHARACTER NO-UNDO.
  DEFINE VARIABLE numberOfDeletedRecords AS INT64 NO-UNDO.
  DEFINE VARIABLE hRecordBuffer AS HANDLE NO-UNDO.
  DEFINE VARIABLE logLevel AS INTEGER NO-UNDO.
  logLevel = 2.

  DEFINE VARIABLE hFileBuffer AS HANDLE NO-UNDO.
  CREATE BUFFER hFileBuffer FOR TABLE "_file".

  DEFINE VARIABLE queryHandle AS HANDLE NO-UNDO.
  CREATE QUERY queryHandle.
  queryHandle:SET-BUFFERS(hFileBuffer).
  queryHandle:QUERY-PREPARE("FOR EACH _file WHERE _file._file-number > 0 AND _file._tbl-type = 'T'").
  queryHandle:QUERY-OPEN().

  queryHandle:GET-FIRST(NO-LOCK).

  _EMPTY_TABLE:
  DO WHILE NOT queryHandle:QUERY-OFF-END:
    thisTable = hFileBuffer:BUFFER-FIELD("_file-name"):BUFFER-VALUE().

    IF emptyTables <> ""
      AND emptyTables <> "ALL"
    THEN DO:
      IF LOOKUP(thisTable, emptyTables) = 0 THEN DO:
        queryHandle:GET-NEXT().
        NEXT _EMPTY_TABLE.
      END.
    END.

    MESSAGE SUBSTITUTE("Deleting records from table &1...", thisTable).

    /* create a buffer for the table*/
    CREATE BUFFER hRecordBuffer FOR TABLE SUBSTITUTE("&1.&2", LDBNAME(1), thisTable) NO-ERROR.
    IF ERROR-STATUS:NUM-MESSAGES > 0 THEN DO:
      errorMessage = "ERROR: Couldn't create buffer for table " + SUBSTITUTE("&1.&2", LDBNAME(1), thisTable) + " !~n".
      DO currentMessage = 1 TO ERROR-STATUS:NUM-MESSAGES:
        errorMessage = errorMessage + "    " + ERROR-STATUS:GET-MESSAGE(currentMessage) + "~n".
      END.
      MESSAGE errorMessage.
      queryHandle:GET-NEXT(NO-LOCK).
      NEXT _EMPTY_TABLE.
    END.
    hRecordBuffer:DISABLE-LOAD-TRIGGERS(TRUE).
    hRecordBuffer:DISABLE-DUMP-TRIGGERS().

    numberOfDeletedRecords = 0.
    _DELETE_RECORDS:
    DO WHILE TRUE:
      _TRANSACTION:
      DO WHILE TRUE TRANSACTION:
        hRecordBuffer:FIND-FIRST("", EXCLUSIVE-LOCK) NO-ERROR.
        IF NOT hRecordBuffer:AVAILABLE THEN DO:
          LEAVE _DELETE_RECORDS.
        END.
        hRecordBuffer:BUFFER-DELETE() NO-ERROR.

        numberOfDeletedRecords = numberOfDeletedRecords + 1.
        IF logLevel >= 3 THEN DO:
          MESSAGE SUBSTITUTE("Deleted record &1...", numberOfDeletedRecords).
        END.
        IF logLevel < 3
          AND numberOfDeletedRecords MOD 10000 = 0
        THEN DO:
          MESSAGE SUBSTITUTE("Deleted record &1...", numberOfDeletedRecords).
        END.
        IF numberOfDeletedRecords MOD 10000 = 0 THEN DO:
          hRecordBuffer:BUFFER-RELEASE().
          LEAVE _TRANSACTION.
        END.
      END.
    END. /*_DELETE_RECORDS*/
    /*TABLE EMPTY*/
    MESSAGE SUBSTITUTE("Deleted &1 records from table &2", numberOfDeletedRecords).
    queryHandle:GET-NEXT(NO-LOCK).
  END. /*_EMPTY_TABLE*/
END.

PROCEDURE LoadData:
  DEFINE INPUT PARAMETER cTables  AS CHARACTER NO-UNDO.
  DEFINE INPUT PARAMETER cDataDir AS CHARACTER NO-UNDO.
  DEFINE VARIABLE iLogLevel AS INTEGER NO-UNDO.

  iLogLevel = 2.

  /*RUN prodict/load_d.r
    (INPUT cTables,
     INPUT cDataDir).*/

  DEFINE VARIABLE cDataFilename  AS CHARACTER NO-UNDO.
  DEFINE VARIABLE cErrorFilename AS CHARACTER NO-UNDO.
  DEFINE VARIABLE cTableName AS CHARACTER  NO-UNDO.
  DEFINE VARIABLE h_fileBuffer AS HANDLE NO-UNDO.

  CREATE BUFFER h_fileBuffer FOR TABLE "_file".

  INPUT FROM OS-DIR(cDataDir).
  _DATAFILE:
  REPEAT:
    IMPORT cDataFilename.
    IF (NOT cDataFilename MATCHES "*~.d")
      OR cDataFilename BEGINS "_"
    THEN DO:
      NEXT _DATAFILE.
    END.

    cTableName = SUBSTRING(cDataFilename, R-INDEX(cDataFilename, '/') + 1).
    cTableName = REPLACE(cTableName,"~.d","").
    cDataFilename = cDataDir + "/" + cDataFilename.
    cErrorFilename = REPLACE(cDataFilename, "~.d", "~.e").

    DEFINE VARIABLE hRecordBuffer AS HANDLE NO-UNDO.
    DEFINE VARIABLE hFieldBuffer AS HANDLE NO-UNDO.
    DEFINE VARIABLE iConter AS INTEGER    NO-UNDO.
    DEFINE VARIABLE cRecord AS CHARACTER  NO-UNDO.
    DEFINE VARIABLE cDelimiter AS CHARACTER  NO-UNDO INITIAL " ".
    DEFINE VARIABLE iRecords AS INTEGER NO-UNDO.
    DEFINE VARIABLE cMessage AS CHARACTER NO-UNDO.
    DEFINE VARIABLE iMessage AS INTEGER NO-UNDO.

    ASSIGN
        cDelimiter     = CHR(32). /* space */

    /* is this a dump name? */
    h_fileBuffer:FIND-FIRST(SUBSTITUTE("WHERE &1._file._dump-name = '&2'", LDBNAME(1), cTableName)) NO-ERROR.
    IF h_fileBuffer:AVAILABLE THEN DO:
      cTableName = h_fileBuffer:BUFFER-FIELD("_file-name"):BUFFER-VALUE().
    END.

    /* create a buffer for the table*/
    CREATE BUFFER hRecordBuffer FOR TABLE SUBSTITUTE("&1.&2", LDBNAME(1), cTableName) NO-ERROR.
    IF ERROR-STATUS:NUM-MESSAGES > 0 THEN DO:
      cMessage = "ERROR: Couldn't create buffer for table " + SUBSTITUTE("&1.&2", LDBNAME(1), cTableName) + " !~n".
      DO iMessage = 1 TO ERROR-STATUS:NUM-MESSAGES:
       cMessage = cMessage + "    " + ERROR-STATUS:GET-MESSAGE(iMessage) + "~n".
      END.
      MESSAGE cMessage.
      NEXT _DATAFILE.
    END.

    DEFINE VARIABLE hFieldHandles AS HANDLE EXTENT 1000 NO-UNDO.
    DEFINE VARIABLE iField        AS INTEGER NO-UNDO.
    DEFINE VARIABLE iTotalFields  AS INTEGER NO-UNDO.
    DEFINE VARIABLE iExtent       AS INTEGER NO-UNDO.
    DEFINE VARIABLE iTotalExtents AS INTEGER NO-UNDO.
    DEFINE VARIABLE iStartExtent  AS INTEGER NO-UNDO.
    DEFINE VARIABLE iTotalEntries AS INTEGER NO-UNDO.
    DEFINE VARIABLE iPosition     AS INTEGER NO-UNDO.
    DEFINE VARIABLE cFieldValue   AS CHARACTER NO-UNDO.
    DEFINE VARIABLE iErrors       AS INTEGER NO-UNDO.
    DEFINE VARIABLE iQuote        AS INTEGER NO-UNDO.
    DEFINE VARIABLE iTotalQuotes  AS INTEGER NO-UNDO.
    
    /* store field handles*/
    iTotalFields = hRecordBuffer:NUM-FIELDS.
    DO iField = 1 TO iTotalFields:
      hFieldHandles[iField] = hRecordBuffer:BUFFER-FIELD(iField).
    END.

    iRecords = 0.
    MESSAGE SUBSTITUTE("Loading records from &1 into table &2...", cDataFilename, cTableName).

    iErrors = 0.
    INPUT STREAM importSteam FROM VALUE(cDataFilename).
    _RECORD:
    REPEAT ON ERROR UNDO, LEAVE:
      IMPORT STREAM importSteam UNFORMATTED cRecord.

      IF cRecord = "~." THEN DO:
        LEAVE _RECORD.
      END.

      iTotalEntries = NUM-ENTRIES(cRecord, cDelimiter).
      _TRANSACTION:
      DO TRANSACTION:
        iRecords = iRecords + 1.
        IF iLogLevel >= 3 THEN DO:
          OUTPUT TO VALUE(cErrorFilename) APPEND.
          MESSAGE SUBSTITUTE("Creating record &1...", iRecords).
          OUTPUT CLOSE.
        END.

        hRecordBuffer:BUFFER-CREATE().
        /* set each fields */
        iPosition = 1.
        _FIELDS:
        DO iField = 1 TO iTotalFields:
          /* none extent fields need to be set to 1 */
          iTotalExtents = hFieldHandles[iField]:EXTENT.
          IF iTotalExtents = 0 THEN DO:
            iStartExtent = 0.
          END.
          ELSE DO:
            iStartExtent = 1.
          END.

          _EXTENTS:
          DO iExtent = iStartExtent TO iTotalExtents:
            /* enough values in line? */
            IF iPosition > iTotalEntries THEN DO:
              OUTPUT TO VALUE(cErrorFilename) APPEND.
              MESSAGE "ERROR: Not enough entries to create record!".
              OUTPUT CLOSE.
              iErrors = iErrors + 1.
              UNDO _RECORD, NEXT _RECORD.
            END.
            cFieldValue = ENTRY(iPosition, cRecord, cDelimiter).

            /* for character strings find the end quote */
            IF cFieldValue BEGINS "~"" THEN DO:
              _GET_QUOTE:
              DO WHILE TRUE:
                /*check empty string*/
                IF LENGTH(cFieldValue) = 2
                  AND cFieldValue = "~"~""
                THEN DO:
                  LEAVE _GET_QUOTE.
                END.

                /* check for last char being a quote (cope with first char being a space) */
                IF SUBSTRING(cFieldValue, LENGTH(cFieldValue), 1) = "~""
                  AND LENGTH(cFieldValue) > 1
                THEN DO:
                  IF iLogLevel >= 4 THEN DO:
                    OUTPUT TO VALUE(cErrorFilename) APPEND.
                    MESSAGE SUBSTITUTE("    (Checking quotes for [&1])", cFieldValue).
                    OUTPUT CLOSE.
                  END.
                  /* we need to check for escaped quotes */
                  iTotalQuotes = 0.
                  _COUNT_QUOTES:
                  DO iQuote = LENGTH(cFieldValue) TO 1 BY -1:
                    IF iLogLevel >= 4 THEN DO:
                      OUTPUT TO VALUE(cErrorFilename) APPEND.
                      MESSAGE SUBSTITUTE("    (Checking char &1 value [&2])", iQuote, SUBSTRING(cFieldValue, iQuote, 1)).
                      OUTPUT CLOSE.
                    END.
                    IF SUBSTRING(cFieldValue, iQuote, 1) = "~"" THEN DO:
                      iTotalQuotes = iTotalQuotes + 1.
                    END.
                    ELSE DO:
                      LEAVE _COUNT_QUOTES.
                    END.
                  END.
                  IF iLogLevel >= 4 THEN DO:
                    OUTPUT TO VALUE(cErrorFilename) APPEND.
                    MESSAGE SUBSTITUTE("    (Found &1 quotes)", iTotalQuotes).
                    OUTPUT CLOSE.
                  END.
                  /* do we have a none-escaped quote? */
                  IF iTotalQuotes MOD 2 = 1 THEN DO:
                    LEAVE _GET_QUOTE.
                  END.
                END.
                /* check if we need to pull in another line*/
                IF iPosition >= iTotalEntries THEN DO:
                  cFieldValue = cFieldValue + "~n".
                  IMPORT STREAM importSteam UNFORMATTED cRecord.
                  iTotalEntries = NUM-ENTRIES(cRecord, cDelimiter).
                  iPosition = 0.
                END.
                iPosition = iPosition + 1.
                cFieldValue = cFieldValue + " " + ENTRY(iPosition, cRecord, cDelimiter).
              END. /*_GET_QUOTE*/

              /* now remove the quotes */
              IF iLogLevel >= 4 THEN DO:
                OUTPUT TO VALUE(cErrorFilename) APPEND.
                MESSAGE SUBSTITUTE("    (Field value: [&1] length: &2)", cFieldValue, LENGTH(cFieldValue)).
                OUTPUT CLOSE.
              END.
              cFieldValue = SUBSTRING(cFieldValue, 2).
              IF iLogLevel >= 4 THEN DO:
                OUTPUT TO VALUE(cErrorFilename) APPEND.
                MESSAGE SUBSTITUTE("    (Field value: [&1] length: &2)", cFieldValue, LENGTH(cFieldValue)).
                OUTPUT CLOSE.
              END.
              cFieldValue = SUBSTRING(cFieldValue, 1, LENGTH(cFieldValue) - 1).
              IF iLogLevel >= 4 THEN DO:
                OUTPUT TO VALUE(cErrorFilename) APPEND.
                MESSAGE SUBSTITUTE("    (Field value: [&1] length: &2)", cFieldValue, LENGTH(cFieldValue)).
                OUTPUT CLOSE.
              END.
              /* replace any double quotes with a single quote */
              cFieldValue = REPLACE(cFieldValue, "~"~"", "~"").
              IF iLogLevel >= 4 THEN DO:
                OUTPUT TO VALUE(cErrorFilename) APPEND.
                MESSAGE SUBSTITUTE("    (Field value: [&1] length: &2)", cFieldValue, LENGTH(cFieldValue)).
                OUTPUT CLOSE.
              END.
            END.

            iPosition = iPosition + 1.

            IF iLogLevel >= 3 THEN DO:
              OUTPUT TO VALUE(cErrorFilename) APPEND.
              MESSAGE SUBSTITUTE("    Assigning value: [&1](&2) to field: &3...", cFieldValue, hFieldHandles[iField]:DATA-TYPE, hFieldHandles[iField]:NAME).
              OUTPUT CLOSE.
            END.
            IF hFieldHandles[iField]:DATA-TYPE = "DATE" THEN DO:
              hFieldHandles[iField]:BUFFER-VALUE(iExtent) = DATE(cFieldValue) NO-ERROR.
            END.
            ELSE IF hFieldHandles[iField]:DATA-TYPE = "LOGICAL" THEN DO:
              hFieldHandles[iField]:BUFFER-VALUE(iExtent) = LOGICAL(cFieldValue) NO-ERROR.
            END.
            ELSE IF hFieldHandles[iField]:DATA-TYPE = "INTEGER"
              OR hFieldHandles[iField]:DATA-TYPE = "DECIMAL"
            THEN DO:
              hFieldHandles[iField]:BUFFER-VALUE(iExtent) = DECIMAL(cFieldValue) NO-ERROR.
            END.
            ELSE DO:
              hFieldHandles[iField]:BUFFER-VALUE(iExtent) = cFieldValue NO-ERROR.
            END.
            IF ERROR-STATUS:NUM-MESSAGES > 0 THEN DO:
              cMessage = "ERROR: Couldn't assign value to field " + hFieldHandles[iField]:NAME + " !~n".
              cMessage = cMessage + "DataType: " + hFieldHandles[iField]:DATA-TYPE + "~n".
              IF cFieldValue <> ? THEN DO:
                cMessage = cMessage + "Value: [" + cFieldValue + "]~n".
              END.
              ELSE DO:
                cMessage = cMessage + "Value: UNKNOWN~n".
              END.
              /*add error message*/                
              DO iMessage = 1 TO ERROR-STATUS:NUM-MESSAGES:
               cMessage = cMessage + "    " + ERROR-STATUS:GET-MESSAGE(iMessage) + "~n".
              END.
              OUTPUT TO VALUE(cErrorFilename) APPEND.
              MESSAGE cMessage.
              OUTPUT CLOSE.
              iErrors = iErrors + 1.
              /*OUTPUT CLOSE.
              INPUT STREAM importSteam CLOSE.
              NEXT _DATAFILE.*/
              NEXT _RECORD.
            END.
          END. /*_EXTENTS*/
        END. /*_FIELDS*/
      END. /*_TRANSACTION*/
    END. /*_RECORD*/

    INPUT STREAM importSteam CLOSE.

    IF iErrors > 0 THEN DO:
      MESSAGE SUBSTITUTE("ERROR: Loaded &1 records with &2 Errors!", iRecords, iErrors).
    END.
    ELSE DO:
      MESSAGE SUBSTITUTE("    Loaded &1 records.", iRecords).
    END.
  END.
END PROCEDURE.

PROCEDURE LoadSchema:
  DEFINE INPUT PARAMETER cSchemaFile AS CHARACTER NO-UNDO.

  RUN prodict/load_df.r
    (INPUT cSchemaFile).
END PROCEDURE.

PROCEDURE LoadSequenceValues:
  DEFINE INPUT PARAMETER cFileName  AS CHARACTER NO-UNDO.
  DEFINE INPUT PARAMETER cDirectory AS CHARACTER NO-UNDO.

  DEFINE VARIABLE cErrorFile AS CHARACTER NO-UNDO.
  
  cErrorFile = cFileName + ".e".

  /*RUN prodict/load_seq.r
    (INPUT cFileName,
     INPUT cDirectory).*/
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
END PROCEDURE.
