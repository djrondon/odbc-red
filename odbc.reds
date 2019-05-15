Red/System [
	Title:   "Red/System ODBC binding"
	Author:  "Christian Ensel"
	File: 	 %odbc.reds
	Rights:  "Copyright (C) 2018 Christian 'CHE' Ensel. All rights reserved."
	License: "BSD-3 - https://github.com/red/red/blob/master/BSD-3-License.txt"
]


;------------------------------------------------------------------------- OS --
;

#switch OS [

Windows [
    #define ODBC_LIBRARY "odbc32.dll"
    #define LIBC_LIBRARY "msvcrt.dll"
]
macOS [
    #define ODBC_LIBRARY "odbc.dylib"
]
#default [
    #define ODBC_LIBRARY "odbc.so.4"
]

]


;---------------------------------------------------------------- LIB_LIBRARY --
;

#import [LIBC_LIBRARY cdecl [

allocate-buffer: "malloc" [
    size    [integer!]
    return: [byte-ptr!]
]

free-buffer: "free" [
    buffer* [byte-ptr!]
]

]]


;---------------------------------------------------------------- SQL defines --
;

integer16!:   alias struct! [lo [byte!] hi [byte!]]
sqlsmallint!: alias struct! [lo [byte!] hi [byte!]]

#define sql-handle!     [pointer! [byte!]]      ;-- There is no specific support in Red/System for C-like void pointers.
                                                ;   The official way is to use a pointer! [byte!] type to represent C void* pointers

#define sql-smallint!   int16-value!
#define sql-return!     sql-smallint!

#define sql-henv!       sql-handle!
#define sql-hdbc!       sql-handle!
#define sql-hstmt!      sql-handle!
#define sql-hwnd!       sql-handle!
#define sql-wchar!      uint16-value!
#define sql-tchar!      sql-wchar!
#define sql-char!       char!
#define sql-integer!    integer!

#define integer16-value!    [integer16! value]
#define integer16-ptr!      integer16!

;-- ODBCVER  Default to ODBC version number (0x0380).

#define ODBCVER                     0380h

;-- return values from functions

#define result-of [FFFFh and]

#define SQL_SUCCESS                     0
#define SQL_SUCCESS_WITH_INFO           1
#define SQL_STILL_EXECUTING             2
#define SQL_NEED_DATA                  99
#define SQL_NO_DATA                   100
#define SQL_ERROR                   FFFFh ; -1
#define SQL_INVALID_HANDLE          FFFEh ; -2

;-- handle type identifiers

#define SQL_HANDLE_ENV                  1
#define SQL_HANDLE_DBC                  2
#define SQL_HANDLE_STMT                 3
#define SQL_HANDLE_DESC                 4

;-- environment attributes
;
#define SQL_ATTR_ODBC_VERSION         200

;-- values for SQL_ATTR_ODBC_VERSION

#define SQL_OV_ODBC2                    2
#define SQL_OV_ODBC3                    3

;-- connection attributes
;
#define SQL_ACCESS_MODE                 101
#define SQL_AUTOCOMMIT                  102
#define SQL_LOGIN_TIMEOUT               103
#define SQL_OPT_TRACE                   104
#define SQL_OPT_TRACEFILE               105
#define SQL_TRANSLATE_DLL               106
#define SQL_TRANSLATE_OPTION            107
#define SQL_TXN_ISOLATION               108
#define SQL_CURRENT_QUALIFIER           109
#define SQL_ODBC_CURSORS                110
#define SQL_QUIET_MODE                  111
#define SQL_PACKET_SIZE                 112
#define SQL_ATTR_ACCESS_MODE            SQL_ACCESS_MODE
#define SQL_ATTR_AUTOCOMMIT             SQL_AUTOCOMMIT
#define SQL_ATTR_CONNECTION_TIMEOUT     113
#define SQL_ATTR_CURRENT_CATALOG        SQL_CURRENT_QUALIFIER
#define SQL_ATTR_DISCONNECT_BEHAVIOR    114
#define SQL_ATTR_ENLIST_IN_DTC          1207
#define SQL_ATTR_ENLIST_IN_XA           1208
#define SQL_ATTR_LOGIN_TIMEOUT          SQL_LOGIN_TIMEOUT
#define SQL_ATTR_ODBC_CURSORS           SQL_ODBC_CURSORS
#define SQL_ATTR_PACKET_SIZE            SQL_PACKET_SIZE
#define SQL_ATTR_QUIET_MODE             SQL_QUIET_MODE
#define SQL_ATTR_TRACE                  SQL_OPT_TRACE
#define SQL_ATTR_TRACEFILE              SQL_OPT_TRACEFILE
#define SQL_ATTR_TRANSLATE_LIB          SQL_TRANSLATE_DLL
#define SQL_ATTR_TRANSLATE_OPTION       SQL_TRANSLATE_OPTION
#define SQL_ATTR_TXN_ISOLATION          SQL_TXN_ISOLATION

#define SQL_DRIVER_NOPROMPT             0

;-- nullability
;
#define SQL_NO_NULLS                    0
#define SQL_NULLABLE                    1
#define SQL_NULLABLE_UNKNOWN            2


;-- whether an attribute is a pointer or not
;
#define SQL_IS_POINTER             -4 ; FFFCh ; -4
#define SQL_IS_UINTEGER            -5 ; FFFBh ; -5
#define SQL_IS_INTEGER             -6 ; FFFAh ; -6
#define SQL_IS_USMALLINT           -7 ; FFF9h ; -7
#define SQL_IS_SMALLINT            -8 ; FFF8h ; -8


;-- SQL data type codes
;

#define SQL_NULL_DATA                  -1

#define SQL_ALL_TYPES                   0

#define SQL_UNKNOWN_TYPE                0
#define SQL_CHAR                        1
#define SQL_NUMERIC                     2
#define SQL_DECIMAL                     3
#define SQL_INTEGER                     4
#define SQL_SMALLINT                    5
#define SQL_FLOAT                       6
#define SQL_REAL                        7
#define SQL_DOUBLE                      8
#define SQL_DATE                        9
#define SQL_TIME                       10
#define SQL_TIMESTAMP                  11
#define SQL_VARCHAR                    12
#define SQL_LONGVARCHAR             FFFFh ; -1
#define SQL_BINARY                  FFFEh ; -2
#define SQL_VARBINARY               FFFDh ; -3
#define SQL_LONGVARBINARY           FFFCh ; -4
#define SQL_BIGINT                  FFFBh ; -5
#define SQL_TINYINT                 FFFAh ; -6
#define SQL_BIT                     FFF9h ; -7
#define SQL_WCHAR                   FFF8h ; -8
#define SQL_WVARCHAR                FFF7h ; -9
#define SQL_WLONGVARCHAR            FFF6h ;-10
#define SQL_GUID                    FFF5h ;-11
#define SQL_TYPE_DATE                  91
#define SQL_TYPE_TIME                  92
#define SQL_TYPE_TIMESTAMP             93


;--  date/time length constants
;

#define SQL_DATE_LEN                10
#define SQL_TIME_LEN                 8  ;-- add P+1 if precision is nonzero
#define SQL_TIMESTAMP_LEN           19  ;-- add P+1 if precision is nonzero


;-- C types
;

#define SQL_C_DEFAULT                   99
#define SQL_C_BIT                       SQL_BIT
#define SQL_C_BINARY                    SQL_BINARY
#define SQL_C_NUMERIC                   SQL_NUMERIC
#define SQL_C_CHAR                      SQL_CHAR
#define SQL_C_WCHAR                     SQL_WCHAR
#define SQL_C_LONG                      SQL_INTEGER
#define SQL_C_DOUBLE                    SQL_DOUBLE
#define SQL_C_DATE                      SQL_DATE
#define SQL_C_TIME                      SQL_TIME
#define SQL_C_TIMESTAMP                 SQL_TIMESTAMP
#define SQL_C_TYPE_DATE                 SQL_TYPE_DATE
#define SQL_C_TYPE_TIME                 SQL_TYPE_TIME
#define SQL_C_TYPE_TIMESTAMP            SQL_TYPE_TIMESTAMP

#define SQL_PARAM_INPUT                 1

#define SQL_MAX_DSN_LENGTH          32  ;-- maximum data source name size

#define SQL_FETCH_NEXT               1
#define SQL_FETCH_FIRST              2
#define SQL_FETCH_FIRST_USER        31
#define SQL_FETCH_FIRST_SYSTEM      32


;-- flags for null-terminated string
#define SQL_NTS                     FFFDh
#define SQL_NTSL                    FFFDh ;(-3L)


SQL_DATE_STRUCT: alias struct! [
    year_lo     [byte!]
    year_hi     [byte!]
    month_lo    [byte!]
    month_hi    [byte!]
    day_lo      [byte!]
    day_hi      [byte!]
    pad1        [byte!]
    pad2        [byte!]
]

SQL_TIME_STRUCT: alias struct! [
    hour_lo     [byte!]
    hour_hi     [byte!]
    minute_lo   [byte!]
    minute_hi   [byte!]
    second_lo   [byte!]
    second_hi   [byte!]
    pad1        [byte!]
    pad2        [byte!]
]

SQL_TIMESTAMP_STRUCT: alias struct! [
    year_lo     [byte!]
    year_hi     [byte!]
    month_lo    [byte!]
    month_hi    [byte!]
    day_lo      [byte!]
    day_hi      [byte!]
    hour_lo     [byte!]
    hour_hi     [byte!]
    minute_lo   [byte!]
    minute_hi   [byte!]
    second_lo   [byte!]
    second_hi   [byte!]
    fraction    [integer!]
]


;-- SQLFreeStmt options

#define SQL_CLOSE                       0
#define SQL_DROP                        1
#define SQL_UNBIND                      2
#define SQL_RESET_PARAMS                3


;-- Null handles returned by SQLAllocHandle

#define SQL_NULL_HENV                   0
#define SQL_NULL_HDBC                   0
#define SQL_NULL_HSTMT                  0
#define SQL_NULL_HDESC                  0 ; ODBCVER >= 0300h


;--------------------------------------------------------------- ODBC_LIBRARY --
;

#import [ODBC_LIBRARY stdcall [

SQLAllocHandle: "SQLAllocHandle" [
    type                    [integer!]
    input                   [sql-handle!]
    output*                 [byte-ptr!]
    return:                 [integer!]
]

SQLBindCol: "SQLBindCol" [
    statement               [sql-handle!]
    column-number           [sqlsmallint! value]
    target-type             [sqlsmallint! value]
    target-value            [byte-ptr!]
    buffer-length           [integer!]
    strlen-or-ind           [pointer! [integer!]]
    return:                 [integer!]
]

SQLBindParameter: "SQLBindParameter" [
    statement               [sql-handle!]
    param-number            [sqlsmallint! value]
    input-output-type       [sqlsmallint! value]
    value-type              [sqlsmallint! value]
    parameter-type          [sqlsmallint! value]
    column-size             [integer!]
    decimal-digits          [sqlsmallint! value]
    param-value-ptr         [byte-ptr!]
    buffer-length           [integer!]
    strlen-or-ind-ptr       [pointer! [integer!]]
    return:                 [integer!]
]

SQLCloseCursor: "SQLCloseCursor" [
    statement               [sql-handle!]
    return:                 [integer!]
]

SQLColumns: "SQLColumnsW" [
    statement               [sql-handle!]
    catalog-name            [c-string!]
    name-length-1           [sqlsmallint! value]
    schema-name             [c-string!]
    name-length-2           [sqlsmallint! value]
    table-name              [c-string!]
    name-length-3           [sqlsmallint! value]
    column-name             [c-string!]
    name-length-4           [sqlsmallint! value]
    return:                 [integer!]
]

SQLConnect: "SQLConnectW" [
    connection              [sql-handle!]
    server-name             [c-string!]
    length-1                [sqlsmallint! value]
    user-name               [c-string!]
    length-2                [sqlsmallint! value]
    authentication          [c-string!]
    length-3                [sqlsmallint! value]
    return:                 [integer!]
]

SQLDataSources: "SQLDataSourcesW" [
    enviromment             [sql-handle!]
    direction               [sqlsmallint! value]
    server-name             [byte-ptr!]
    buffer1-length          [sqlsmallint! value]
    server-name-length      [sqlsmallint!]
    description-name        [byte-ptr!]
    buffer2-length          [sqlsmallint! value]
    description-length      [sqlsmallint!]
    return:                 [integer!]
]

SQLDescribeCol: "SQLDescribeColW" [
    statement               [sql-handle!]
    column-number           [sqlsmallint! value]
    column-name             [c-string!]
    buffer-length           [sqlsmallint! value]
    name-length             [sqlsmallint!]
    sql-type                [sqlsmallint!]
    column-size             [pointer! [integer!]]
    decimal-digits          [sqlsmallint!]
    nullable                [sqlsmallint!]
    return:                 [integer!]
]

SQLDisconnect: "SQLDisconnect" [
    connection              [sql-handle!]
    return:                 [integer!]
]

SQLDriverConnect: "SQLDriverConnectW" [
    connection              [sql-handle!]
    window-handle           [byte-ptr!]
    in-connection-string    [byte-ptr!]
    string-length-1         [integer!]
    out-connection-string   [byte-ptr!]
    buffer-length           [integer!]
    string-length-2-ptr     [pointer! [integer!]]
    driver-completion       [integer!]
    return:                 [integer!]
]

SQLDrivers: "SQLDriversW" [
    enviromment             [sql-handle!]
    direction               [sqlsmallint! value]
    description             [byte-ptr!]
    buffer1-length          [sqlsmallint! value]
    description-length      [sqlsmallint!]
    attributes              [byte-ptr!]
    buffer2-length          [sqlsmallint! value]
    attributes-length       [sqlsmallint!]
    return:                 [integer!]
]

SQLExecute: "SQLExecute" [
    statement               [sql-handle!]
    return:                 [integer!]
]

SQLFetch: "SQLFetch" [
    statement               [sql-handle!]
    return:                 [integer!]
]

SQLFreeHandle: "SQLFreeHandle" [
    type                    [integer!]
    statement               [sql-handle!]
    return:                 [integer!]
]

SQLFreeStmt: "SQLFreeStmt" [
    statement               [sql-handle!]
    option                  [sqlsmallint! value]
    return:                 [integer!]
]

SQLGetDiagRec: "SQLGetDiagRecW" [
    type                    [integer!]
    handle                  [sql-handle!]
    record                  [integer!]
    state                   [byte-ptr!]
    error-ptr               [pointer! [integer!]]
    message                 [byte-ptr!]
    length                  [integer!]
    length-ptr              [pointer! [integer!]]
    return:                 [integer!]
]

SQLGetTypeInfo: "SQLGetTypeInfo" [
    statement               [sql-handle!]
    datatype                [sqlsmallint! value]
    return:                 [integer!]
]

SQLNumResultCols: "SQLNumResultCols" [
    statement               [sql-handle!]
    column-count            [byte-ptr!]
    return:                 [integer!]
]

SQLPrepare: "SQLPrepareW" [
    statement               [sql-handle!]
    statement-text          [byte-ptr!]
    text-length             [integer!]
    return:                 [integer!]
]

SQLRowCount: "SQLRowCount" [
    statement               [sql-handle!]
    row-count-ptr           [pointer! [integer!]]
    return:                 [integer!]
]

SQLSetConnectAttr: "SQLSetConnectAttr" [
    connection              [sql-handle!]
    attribute               [integer!]
    value                   [integer!]
    length                  [integer!]
    return:                 [integer!]
]

SQLSetEnvAttr: "SQLSetEnvAttr" [
    environment             [sql-handle!]
    attribute               [integer!]
    value                   [integer!]
    length                  [integer!]
    return:                 [integer!]
]

SQLTables: "SQLTablesW" [
    statement               [sql-handle!]
    catalog-name            [c-string!]
    name-length-1           [sqlsmallint! value]
    schema-name             [c-string!]
    name-length-2           [sqlsmallint! value]
    table-name              [c-string!]
    name-length-3           [sqlsmallint! value]
    table-type              [c-string!]
    name-length-4           [sqlsmallint! value]
    return:                 [integer!]
]

SQLTest: "SQLTest" [
    column-number           [sqlsmallint! value]
    return:                 [integer!]
]

]]