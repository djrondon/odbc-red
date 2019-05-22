Red [
	Title:   "Red ODBC binding"
	Author:  "Christian Ensel"
	File: 	 %odbc.red
	Rights:  "Copyright (C) 2019 Christian 'che' Ensel. All rights reserved."
	License: "BSD-3 - https://github.com/red/red/blob/master/BSD-3-License.txt"

    Issues: {
        - insufficient error handling
        - incomplete parameter binding and datatype conversion
        - ugly int16 / sqlsmallint handling
        - hacky buggy utf8/16 / (w/t)char / unicode handling
        - Windows support only
        - no pure Red/System API, usable only from Red
    }
]

#system [
    #include %odbc.reds

    #define SET_INT16(int16 value) [
        int16/lo: as byte! value and FFh
        int16/hi: as byte! value >> 8 and FFh
        int16
    ]

    #define GET_INT16(int16) [
        ((as integer! int16/hi) << 8 or (as integer! int16/lo))
    ]

    #define ODBC_DEBUG          comment
    #define ODBC_DEBUG_BYTES    comment
   ;#define ODBC_DEBUG          print
   ;#define ODBC_DEBUG_BYTES    print-bytes

    #define ODBC_REJECT(value)  [if result = value]

    odbc: context [

        ;------------------------------------------------------------ structs --
        ;

        environment!: alias struct! [
            henv        [sql-handle!]
        ]

        environment: declare environment!

        connection!: alias struct! [
            hdbc        [sql-handle!]
            dsn         [c-string!]
        ]

        column!: alias struct! [
            name        [c-string!]
            name-length [integer!]
            buffer      [byte-ptr!]
            buffer-size [integer!]
            sql-type    [integer!]
            column-size [integer!]
            digits      [integer!]
            nullable    [integer!]
            strlen-ind  [integer!]
            size        [sqlsmallint! value]
            c-type      [sqlsmallint! value]
        ]

        param!: alias struct! [
            size        [integer!]
            offset      [integer!]
        ]

        statement!: alias struct! [
            connection  [byte-ptr!]
            hstmt       [sql-handle!]
            columns     [column!]
            columns-cnt [integer!]
            params      [param!]
            params-cnt  [integer!]
            params-buf  [byte-ptr!]
        ]


        ;-------------------------------------------------------- print-bytes --
        ;

        print-bytes: func [
            bytes   [byte-ptr!]
            cnt     [integer!]
            /local
                byte hi lo
        ][
            loop cnt [
                byte: bytes/1
                hi:   as integer! ((byte and #"^(F0)") >>> 4)
                lo:   as integer!   byte and #"^(0F)"
                switch hi [
                     0 [print "0"]  1 [print "1"]  2 [print "2"]  3 [print "3"]
                     4 [print "4"]  5 [print "5"]  6 [print "6"]  7 [print "7"]
                     8 [print "8"]  9 [print "9"] 10 [print "a"] 11 [print "b"]
                    12 [print "c"] 13 [print "d"] 14 [print "e"] 15 [print "f"]
                ]
                switch lo [
                     0 [print "0"]  1 [print "1"]  2 [print "2"]  3 [print "3"]
                     4 [print "4"]  5 [print "5"]  6 [print "6"]  7 [print "7"]
                     8 [print "8"]  9 [print "9"] 10 [print "a"] 11 [print "b"]
                    12 [print "c"] 13 [print "d"] 14 [print "e"] 15 [print "f"]
                ]
                print " "
                bytes: bytes + 1
            ]
            print lf
        ]


        ;------------------------------------------------------- wide-length? --
        ;

        wide-length?: func [
            "Returns length in wide chars, terminating null char included."
            wide        [c-string!]
            return:     [integer!]
            /local
                i j
        ][
            i: -1 j: 0
            until [
                i: i + 2 j: j + 2
                all [wide/i = #"^@" wide/j = #"^@"]
            ]
            j / 2
        ]


        ;--------------------------------------------------- open-environment --
        ;

        open-environment: func [
            /local
                result
        ][
            ODBC_DEBUG ["OPEN-ENVIRONMENT" lf]

            unless environment/henv = null [
                SET_RETURN((handle/box as integer! environment)) exit
            ]

            ;-- allocate environment handle
            ;
            result: result-of SQLAllocHandle SQL_HANDLE_ENV
                                             null
                                             as byte-ptr! :environment/henv

            ODBC_DEBUG ["SQLAllocHandle " result lf]

            ODBC_REJECT((SQL_ERROR or SQL_INVALID_HANDLE)) [
                SET_RETURN((diagnose-error SQL_HANDLE_ENV null)) exit
            ]

            ;-- set SQL_ATTR_ODBC_VERSION environment attribute.
            ;
            result: result-of SQLSetEnvAttr environment/henv
                                            SQL_ATTR_ODBC_VERSION
                                            SQL_OV_ODBC2
                                            0

            ODBC_DEBUG ["SQLSetEnvAttr " result lf]

            ODBC_REJECT((SQL_ERROR or SQL_INVALID_HANDLE)) [
                SET_RETURN((diagnose-error SQL_HANDLE_ENV environment/henv)) exit
            ]

            SET_RETURN((handle/box as integer! environment))
        ]


        ;---------------------------------------------------- open-connection --
        ;

        open-connection: func [
            datasource  [red-string!]
            /local
                connection result conn-str conn-len
        ][
            ODBC_DEBUG ["OPEN-CONNECTION" lf]

            ;-- allocate connection handle
            ;
            connection: as connection! allocate-buffer size? connection!

            result: result-of SQLAllocHandle SQL_HANDLE_DBC
                                             environment/henv
                                             as byte-ptr! :connection/hdbc

            ODBC_DEBUG ["SQLAllocHandle " result lf]

            ODBC_REJECT((SQL_ERROR or SQL_INVALID_HANDLE)) [
                SET_RETURN((diagnose-error SQL_HANDLE_ENV environment/henv)) exit
            ]

            ;-- set SQL_ATTR_LOGIN_TIMEOUT connection attribute.
            ;
            result: result-of SQLSetConnectAttr connection/hdbc
                                                SQL_ATTR_LOGIN_TIMEOUT
                                                5                               ;-- FIXME: hardcoded value
                                                SQL_IS_INTEGER


            ODBC_DEBUG ["SQLSetConnectAttr " result lf]

            ODBC_REJECT((SQL_ERROR or SQL_INVALID_HANDLE)) [
                SET_RETURN((diagnose-error SQL_HANDLE_DBC connection/hdbc)) exit
            ]

            ;-- connect to driver
            ;
            conn-str: unicode/to-utf16 datasource
            conn-len: wide-length? conn-str

            result: result-of SQLDriverConnect connection/hdbc
                                               null
                                               as byte-ptr! conn-str
                                               conn-len
                                               null
                                               0
                                               null
                                               SQL_DRIVER_NOPROMPT

            ODBC_DEBUG ["SQLDriverConnect " result lf]

            ODBC_REJECT((SQL_ERROR or SQL_INVALID_HANDLE)) [
                SET_RETURN((diagnose-error SQL_HANDLE_DBC connection/hdbc)) exit
            ]

            SET_RETURN((handle/box as integer! connection))
        ]


        ;----------------------------------------------------- open-statement --
        ;

        open-statement: function [
            holder      [red-handle!]
            /local
                connection statement result
        ][
            ODBC_DEBUG ["OPEN-STATEMENT" lf]

            connection: as connection! holder/value
            statement:  as statement!  allocate-buffer size? statement!

            ;-- allocate statement handle
            ;
            result: result-of SQLAllocHandle SQL_HANDLE_STMT
                                             connection/hdbc
                                             as byte-ptr! :statement/hstmt

            ODBC_DEBUG ["SQLAllocHandle " result lf]

            ODBC_REJECT((SQL_ERROR or SQL_INVALID_HANDLE)) [
                SET_RETURN((diagnose-error SQL_HANDLE_DBC connection/hdbc)) exit
            ]

            SET_RETURN((handle/box as integer! statement))
        ]


        ;------------------------------------------------ translate-statement --
        ;

        translate-statement: func [
            holder      [red-handle!]
            sql         [red-string!]
            /local
                connection query text result in-sql out-sql out-str out size length i j bytes buf
        ][
            ODBC_DEBUG ["TRANSLATE-STATEMENT" lf]

            connection: as connection! holder/value

            ;-- prepare statement
            ;
            in-sql:     unicode/to-utf16 sql                                    ;-- null terminated utf16
            length:     0

            result:     result-of SQLNativeSql connection/hdbc
                                               in-sql
                                               wide-length? in-sql
                                               null
                                               0
                                              :length

            ODBC_DEBUG ["SQLNativeSql " result lf]

            ODBC_REJECT((SQL_ERROR or SQL_INVALID_HANDLE)) [
                SET_RETURN((diagnose-error SQL_HANDLE_DBC connection/hdbc)) exit
            ]

            size:       length << 1 + 2
            out-sql:    as c-string! allocate size

            result:     result-of SQLNativeSql connection/hdbc
                                               in-sql
                                               wide-length? in-sql
                                               out-sql
                                               size
                                              :length

            ODBC_DEBUG ["SQLNativeSql " result lf]

            ODBC_REJECT((SQL_ERROR or SQL_INVALID_HANDLE)) [
                SET_RETURN((diagnose-error SQL_HANDLE_DBC connection/hdbc)) exit
            ]

            SET_RETURN((string/load out-sql length UTF-16LE))
        ]


        ;-------------------------------------------------- prepare-statement --
        ;

        prepare-statement: func [
            holder      [red-handle!]
            params      [red-block!]
            /local
                statement query text result red-str wide-str bytes i j
        ][
            ODBC_DEBUG ["PREPARE-STATEMENT" lf]

            statement: as statement! holder/value

            ;-- prepare statement
            ;
            red-str:    as red-string! block/rs-head params
            wide-str:   unicode/to-utf16 red-str                                ;-- null terminated utf16

            result:     result-of SQLPrepare statement/hstmt
                                             wide-str
                                             wide-length? wide-str

            ODBC_DEBUG ["SQLPrepare " result lf]

            ODBC_REJECT((SQL_ERROR or SQL_INVALID_HANDLE)) [
                SET_RETURN((diagnose-error SQL_HANDLE_STMT statement/hstmt)) exit
            ]

            SET_RETURN((logic/box true))
        ]


        ;------------------------------------------------------- list-sources --
        ;

        list-sources: func [
            sources     [red-block!]
            /local
                direction result
                server-name server-name-length buffer1-length
                description description-length buffer2-length
        ][
            ODBC_DEBUG ["LIST-SOURCES" lf]

            ;-- list sources
            ;
            direction:          declare sqlsmallint!
            server-name-length: declare sqlsmallint!
            buffer1-length:     declare sqlsmallint!
            description-length: declare sqlsmallint!
            buffer2-length:     declare sqlsmallint!

            server-name:        allocate 1024
            description:        allocate 4096

            SET_INT16(buffer1-length 1024)
            SET_INT16(buffer2-length 4096)

            SET_INT16(direction SQL_FETCH_FIRST)
            until [
                result: result-of SQLDataSources environment/henv
                                                 direction
                                                 server-name
                                                 buffer1-length
                                                 server-name-length
                                                 description
                                                 buffer2-length
                                                 description-length

                ODBC_DEBUG ["SQLDataSources " result lf]

                ODBC_REJECT((SQL_ERROR or SQL_INVALID_HANDLE)) [
                    SET_RETURN((diagnose-error SQL_HANDLE_ENV environment/henv)) exit
                ]

                string/load-in as c-string! server-name GET_INT16(server-name-length) sources UTF-16LE
                string/load-in as c-string! description GET_INT16(description-length) sources UTF-16LE

                SET_INT16(direction SQL_FETCH_NEXT)

                result = SQL_NO_DATA
            ]

            SET_RETURN((logic/box true))
        ]


        ;------------------------------------------------------- list-drivers --
        ;

        list-drivers: func [
            drivers     [red-block!]
            /local
                direction result
                description description-length buffer1-length
                attributes  attributes-length  buffer2-length
        ][
            ODBC_DEBUG ["LIST-DRIVERS" lf]

            ;-- list drivers
            ;
            direction:          declare sqlsmallint!
            description-length: declare sqlsmallint!
            buffer1-length:     declare sqlsmallint!
            attributes-length:  declare sqlsmallint!
            buffer2-length:     declare sqlsmallint!

            description:        allocate 1024
            attributes:         allocate 4096

            SET_INT16(buffer1-length 1024)
            SET_INT16(buffer2-length 4096)

            SET_INT16(direction SQL_FETCH_FIRST)
            until [
                result: result-of SQLDrivers environment/henv
                                             direction
                                             description
                                             buffer1-length
                                             description-length
                                             attributes
                                             buffer2-length
                                             attributes-length

                ODBC_DEBUG ["SQLDrivers " result lf]

                ODBC_REJECT((SQL_ERROR or SQL_INVALID_HANDLE)) [
                    SET_RETURN((diagnose-error SQL_HANDLE_ENV environment/henv)) exit
                ]

                string/load-in as c-string! description GET_INT16(description-length) drivers UTF-16LE
                string/load-in as c-string! attributes  GET_INT16( attributes-length) drivers UTF-16LE

                SET_INT16(direction SQL_FETCH_NEXT)

                result = SQL_NO_DATA
            ]

            SET_RETURN((logic/box true))
        ]


        ;-------------------------------------------------- catalog-statement --
        ;

        _tables:        symbol/make "tables"
        _columns:       symbol/make "columns"
        _types:         symbol/make "types"

        catalog-statement: func [
            holder      [red-handle!]
            catalog     [red-block!]
            /local
                connection statement entity word sym all-types length result
        ][
            ODBC_DEBUG ["CATALOG-STATEMENT" lf]

            statement:  as statement! holder/value
            entity:     block/rs-head catalog
            word:       as red-word! entity
            sym:        symbol/resolve word/symbol

            case [
                sym = _tables [
                    length: declare sqlsmallint!
                    SET_INT16(length 0)

                    result: result-of SQLTables statement/hstmt
                                                null length
                                                null length
                                                null length
                                                null length

                    ODBC_DEBUG ["SQLTables " result lf]

                    ODBC_REJECT((SQL_ERROR or SQL_INVALID_HANDLE)) [
                        SET_RETURN((diagnose-error SQL_HANDLE_STMT statement/hstmt)) exit
                    ]
                ]
                sym = _columns [
                    length: declare sqlsmallint!
                    SET_INT16(length 0)

                    result: result-of SQLColumns statement/hstmt
                                                 null length
                                                 null length
                                                 null length
                                                 null length

                    ODBC_DEBUG ["SQLColumns " result lf]

                    ODBC_REJECT((SQL_ERROR or SQL_INVALID_HANDLE)) [
                        SET_RETURN((diagnose-error SQL_HANDLE_STMT statement/hstmt)) exit
                    ]
                ]
                sym = _types [
                    all-types: declare sqlsmallint!
                    SET_INT16(all-types SQL_ALL_TYPES)

                    result: result-of SQLGetTypeInfo statement/hstmt
                                                     all-types

                    ODBC_DEBUG ["SQLGetTypeInfo " result lf]

                    ODBC_REJECT((SQL_ERROR or SQL_INVALID_HANDLE)) [
                        SET_RETURN((diagnose-error SQL_HANDLE_STMT statement/hstmt)) exit
                    ]
                ]
            ]

            SET_RETURN((logic/box true))
        ]


        ;----------------------------------------------------- bind-parameter --
        ;

        bind-parameter: func [
            statement   [statement!]
            param       [param!]
            num         [integer!]
            value       [red-value!]
            /local
                result io-type c-type sql-type digits count buffer
                int-buffer float-buffer str-buffer column-size strlen-ind
                red-str wide-str wide-len
        ][
            ODBC_DEBUG ["BIND-PARAMETER" lf]

            io-type:         declare sqlsmallint!
            sql-type:        declare sqlsmallint!
            c-type:          declare sqlsmallint!
            digits:          declare sqlsmallint!
            count:           declare sqlsmallint!
            strlen-ind:      0
            column-size:     0

            SET_INT16(count         num)
            SET_INT16(io-type       SQL_PARAM_INPUT)
            SET_INT16(digits        0)

            switch TYPE_OF(value) [
                TYPE_INTEGER [
                    SET_INT16(c-type    SQL_C_LONG)
                    SET_INT16(sql-type  SQL_INTEGER)
                    int-buffer:         as pointer! [integer!] statement/params-buf + param/offset
                    int-buffer/value:   integer/get as red-value! value
                    buffer:             as byte-ptr! int-buffer
                ]
                TYPE_FLOAT [
                    SET_INT16(c-type    SQL_C_DOUBLE)
                    SET_INT16(sql-type  SQL_DOUBLE)
                    float-buffer:       as pointer! [float!] statement/params-buf + param/offset
                    float-buffer/value: float/get as red-value! value
                    buffer:             as byte-ptr! float-buffer
                ]
                TYPE_STRING [
                    SET_INT16(c-type    SQL_C_WCHAR)
                    SET_INT16(sql-type  SQL_VARCHAR)
                    strlen-ind:         SQL_NTS
                    red-str:            as red-string! value
                    wide-str:           unicode/to-utf16 red-str                ;-- null terminated
                    wide-len:           wide-length? wide-str
                    column-size:        wide-len - 1                            ;-- FIXME: or string/rs-length? red-str
                    str-buffer:         statement/params-buf + param/offset
                    copy-memory str-buffer as byte-ptr! wide-str wide-len << 1
                    buffer:             str-buffer
                ]
                TYPE_LOGIC [
                    SET_INT16(c-type    SQL_C_LONG)
                    SET_INT16(sql-type  SQL_BIT)
                    int-buffer:         as pointer! [integer!] statement/params-buf + param/offset
                    int-buffer/value:   either logic/get as red-value! value [1] [0]
                    buffer:             as byte-ptr! int-buffer
                ]
                default [
                    SET_INT16(c-type    SQL_C_DEFAULT)
                    SET_INT16(sql-type  SQL_NULL_DATA)
                    strlen-ind:         SQL_NULL_DATA
                    buffer:             null
                ]
            ]

            result: result-of SQLBindParameter statement/hstmt
                                               count
                                               io-type
                                               c-type
                                               sql-type
                                               column-size
                                               digits
                                               buffer
                                               param/size
                                              :strlen-ind

            ODBC_DEBUG ["SQLBindParameter " result lf]

            ODBC_REJECT((SQL_ERROR or SQL_INVALID_HANDLE)) [
                SET_RETURN((diagnose-error SQL_HANDLE_STMT statement/hstmt)) exit
            ]

            SET_RETURN((logic/box true))
        ]


        ;-------------------------------------------------- execute-statement --
        ;

        execute-statement: func [
            holder      [red-handle!]
            sql         [red-block!]
            /local
                statement result value p param size
        ][
            ODBC_DEBUG ["EXECUTE-STATEMENT" lf]

            statement:  as statement! holder/value

            ;-- free buffers
            ;
            unless statement/params = null [                                    ;-- first, free previously allocated params/buffer
                free-buffer as byte-ptr! statement/params
            ]
            unless statement/params-buf = null [
                free-buffer statement/params-buf
            ]

            ;-- allocate params
            ;
            statement/params-cnt:   (block/rs-length? sql) - 1
            statement/params:       as param! allocate-buffer statement/params-cnt * size? byte-ptr!

            ;-- caluclate buffer size(s)
            ;
            value: (block/rs-head sql) + 1                                      ;-- skip statement string
            param: statement/params
            p:     1

            size:  0
            loop statement/params-cnt [
                param/offset: size

                switch TYPE_OF(value) [
                    TYPE_INTEGER [param/size: 4]
                    TYPE_FLOAT   [param/size: 8]
                    TYPE_LOGIC   [param/size: 4]
                    TYPE_STRING  [param/size: (wide-length? unicode/to-utf16 as red-string! value) << 1 + 2 ]
                    default      [param/size: 0]
                ]

                size:  size  + param/size
                value: value + 1
                param: param + 1
                p:     p     + 1
            ]

            ;-- allocate buffer
            ;
            statement/params-buf: allocate-buffer size

            ;-- bind parameters
            ;
            value: (block/rs-head sql) + 1
            param: statement/params
            p:     1

            loop statement/params-cnt [
                bind-parameter statement param p value

                value: value + 1
                param: param + 1
                p:     p     + 1
            ]

            ;-- execute statement
            ;
            result: result-of SQLExecute statement/hstmt

            ODBC_DEBUG ["SQLExecute " result lf]

            ODBC_REJECT((SQL_ERROR or SQL_INVALID_HANDLE)) [
                SET_RETURN((diagnose-error SQL_HANDLE_STMT statement/hstmt)) exit
            ]

            SET_RETURN((logic/box true))
        ]


        ;---------------------------------------------------- describe-column --
        ;

        describe-column: func [
            hstmt       [sql-handle!]
            column      [column!]
            num         [integer!]
            columns     [red-block!]
            /local
                result count buffer-size name-length sql-type digits nullable
        ][
            ODBC_DEBUG ["DESCRIBE-COLUMN" lf]

            count:          declare sqlsmallint!
            buffer-size:    declare sqlsmallint!
            name-length:    declare sqlsmallint!
            sql-type:       declare sqlsmallint!
            digits:         declare sqlsmallint!
            nullable:       declare sqlsmallint!

            column/name:    as c-string! allocate-buffer 256

            SET_INT16(count num)
            SET_INT16(buffer-size 256)

            result: result-of SQLDescribeCol hstmt
                                             count
                                             column/name
                                             buffer-size
                                             name-length
                                             sql-type
                                            :column/column-size
                                             digits
                                             nullable

            ODBC_DEBUG ["SQLDescribeCol " result lf]

            ODBC_REJECT((SQL_ERROR or SQL_INVALID_HANDLE)) [
                SET_RETURN((diagnose-error SQL_HANDLE_STMT hstmt)) exit
            ]

            column/name-length: GET_INT16(name-length)
            column/sql-type:    GET_INT16(sql-type)
            column/digits:      GET_INT16(digits)
            column/nullable:    GET_INT16(nullable)

            string/load-in column/name column/name-length columns UTF-16LE

            SET_RETURN((logic/box true))
        ]


        ;-------------------------------------------------------- bind-column --
        ;

        bind-column: func [
            hstmt       [sql-handle!]
            column      [column!]
            num         [integer!]
            /local
                result count
        ][
            ODBC_DEBUG ["BIND-COLUMN" lf]

            count:  declare sqlsmallint!

            column/buffer-size: 0
            column/buffer:      null

            switch column/sql-type [
                SQL_CHAR
                SQL_VARCHAR
                SQL_LONGVARCHAR [
                    SET_INT16(column/c-type SQL_C_WCHAR)                        ;-- FIXME: Okay?
                    column/buffer-size:     (column/column-size + 1) << 1
                ]
                SQL_WCHAR
                SQL_WVARCHAR
                SQL_WLONGVARCHAR [
                    SET_INT16(column/c-type SQL_C_WCHAR)
                    column/buffer-size:     (column/column-size + 1) << 1
                ]
                SQL_DECIMAL
                SQL_NUMERIC [
                    SET_INT16(column/c-type SQL_C_CHAR)
                    column/buffer-size:     128                                 ;-- FIXME: Why?
                ]
                SQL_SMALLINT
                SQL_INTEGER [
                    SET_INT16(column/c-type SQL_C_LONG)
                    column/buffer-size:     4
                ]
                SQL_REAL
                SQL_FLOAT
                SQL_DOUBLE [
                    SET_INT16(column/c-type SQL_C_DOUBLE)
                    column/buffer-size:     8
                ]
                SQL_BIT [
                    SET_INT16(column/c-type SQL_C_LONG)
                    column/buffer-size:     4
                ]
                SQL_TINYINT [
                    SET_INT16(column/c-type SQL_C_LONG)
                    column/buffer-size:     4
                ]
                SQL_BIGINT [
                    print ["SQL_BIGINT dataype not supported." lf]
                ]
                SQL_BINARY
                SQL_VARBINARY
                SQL_LONGVARBINARY [
                    print ["SQL_((LONG)VAR)BINARY dataypes not supported." lf]
                ]
;               SQL_DATE [
;                   SET_INT16(column/c-type SQL_DATE)
;                   column/buffer-size:     size? SQL_DATE_STRUCT
;               ]
;               SQL_TYPE_DATE [
;                   SET_INT16(column/c-type SQL_C_TYPE_DATE)
;                   column/buffer-size:     size? SQL_DATE_STRUCT
;               ]
                SQL_DATE
                SQL_TYPE_DATE [
                    SET_INT16(column/c-type SQL_C_CHAR)
                    column/buffer-size:     11
                ]
;               SQL_TIME [
;                   SET_INT16(column/c-type SQL_TIME)
;                   column/buffer-size:     size? SQL_TIME_STRUCT
;               ]
;               SQL_TYPE_TIME [
;                   SET_INT16(column/c-type SQL_C_TYPE_TIME)
;                   column/buffer-size:     size? SQL_TIME_STRUCT
;               ]
                SQL_TIME
                SQL_TYPE_TIME [
                    SET_INT16(column/c-type SQL_C_CHAR)
                    column/buffer-size:     9
                ]
;               SQL_TIMESTAMP [
;                   SET_INT16(column/c-type SQL_TIMESTAMP)
;                   column/buffer-size:     size? SQL_TIMESTAMP_STRUCT
;               ]
;               SQL_TYPE_TIMESTAMP [
;                   SET_INT16(column/c-type SQL_C_TYPE_TIMESTAMP)
;                   column/buffer-size:     size? SQL_TIMESTAMP_STRUCT
;               ]
                SQL_TIMESTAMP
                SQL_TYPE_TIMESTAMP [
                    SET_INT16(column/c-type SQL_C_CHAR)
                    column/buffer-size:     20
                ]
               ;SQL_INTERVAL_MONTH
               ;SQL_INTERVAL_YEAR
               ;SQL_INTERVAL_YEAR_TO_MONTH
               ;SQL_INTERVAL_DAY
               ;SQL_INTERVAL_HOUR
               ;SQL_INTERVAL_MINUTE
               ;SQL_INTERVAL_SECOND
               ;SQL_INTERVAL_DAY_TO_HOUR
               ;SQL_INTERVAL_DAY_TO_MINUTE
               ;SQL_INTERVAL_DAY_TO_SECOND
               ;SQL_INTERVAL_HOUR_TO_MINUTE
               ;SQL_INTERVAL_HOUR_TO_SECOND
               ;SQL_INTERVAL_MINUTE_TO_SECOND [
               ;    print ["SQL interval dataypes not supported." lf]
               ;]
                SQL_GUID [
                    SET_INT16(column/c-type SQL_C_WCHAR)
                    column/buffer-size:     (column/column-size + 1) << 1
                ]
                default [
                    print ["Unknown dataype " column/sql-type " not supported." lf]
                ]
            ]

            unless zero? column/buffer-size [
                column/buffer: allocate-buffer column/buffer-size
            ]

            SET_INT16(count num)

            result: result-of SQLBindCol hstmt
                                         count
                                         column/c-type
                                         column/buffer                      ;-- incl. null-termination
                                         column/buffer-size                 ;           -"-
                                        :column/strlen-ind

            ODBC_DEBUG ["SQLBindCol " result lf]

            ODBC_REJECT((SQL_ERROR or SQL_INVALID_HANDLE)) [
                SET_RETURN((diagnose-error SQL_HANDLE_STMT hstmt)) exit
            ]

            SET_RETURN((logic/box true))
        ]


        ;------------------------------------------------- describe-statement --
        ;

        describe-statement: func [
            holder      [red-handle!]
            columns     [red-block!]
            /local
                statement result count c column rows
        ][
            ODBC_DEBUG ["DESCRIBE-STATEMENT" lf]

            count:      declare sqlsmallint!
            rows:       0

            statement:  as statement! holder/value

            result:     result-of SQLNumResultCols statement/hstmt
                                                   as byte-ptr! count

            ODBC_DEBUG ["SQLNumResultCols " result lf]

            ODBC_REJECT((SQL_ERROR or SQL_INVALID_HANDLE)) [
                SET_RETURN((diagnose-error SQL_HANDLE_STMT statement/hstmt)) exit
            ]

            statement/columns-cnt:  GET_INT16(count)
            statement/columns:      as column! allocate-buffer statement/columns-cnt * size? column!

            either zero? statement/columns-cnt [
                result:     result-of SQLRowCount statement/hstmt
                                                 :rows

                ODBC_DEBUG ["SQLRowCount " result lf]

                ODBC_REJECT((SQL_ERROR or SQL_INVALID_HANDLE)) [
                    SET_RETURN((diagnose-error SQL_HANDLE_STMT statement/hstmt)) exit
                ]

                integer/make-in columns rows
            ][
                column: statement/columns
                c:      1

                loop statement/columns-cnt [
                    describe-column statement/hstmt column c columns

                    bind-column     statement/hstmt column c

                    column: column + 1
                    c:      c + 1
                ]
            ]

            SET_RETURN((logic/box true))
        ]


        ;------------------------------------------------------- fetch-column --
        ;

        fetch-column: func [
            hstmt       [sql-handle!]
            row         [red-block!]
            column      [column!]
            /local
                result buffer value integer-ptr float-ptr red-date red-time
                date-ptr time-ptr timestamp-ptr dy dm dd th tm ts tf
        ][
            ODBC_DEBUG ["FETCH-COLUMN" lf]

            if column/strlen-ind = SQL_NULL_DATA [                              ;-- early exit with NONE value
                none/make-in row
                exit
            ]

            switch column/sql-type [
                SQL_CHAR
                SQL_VARCHAR
                SQL_LONGVARCHAR [
                    value: as c-string! column/buffer
                    string/load-in as c-string! column/buffer column/strlen-ind >> 1 row UTF-16LE
                ]
                SQL_WCHAR
                SQL_WVARCHAR
                SQL_WLONGVARCHAR [
                    value: as c-string! column/buffer
                    string/load-in as c-string! column/buffer column/strlen-ind >> 1 row UTF-16LE
                ]
                SQL_DECIMAL
                SQL_NUMERIC [
                    value: as c-string! column/buffer
                    string/load-in as c-string! column/buffer column/strlen-ind row UTF-8
                ]
                SQL_SMALLINT
                SQL_INTEGER [
                    integer-ptr: as [pointer! [integer!]] column/buffer
                    integer/make-in row integer-ptr/value
                ]
                SQL_REAL
                SQL_FLOAT
                SQL_DOUBLE [
                    float-ptr: as struct! [int1 [integer!] int2 [integer!]] column/buffer
                    float/make-in row float-ptr/int2 float-ptr/int1
                ]
                SQL_BIT [
                    integer-ptr: as [pointer! [integer!]] column/buffer
                    logic/make-in row not zero? integer-ptr/value
                ]
                SQL_TINYINT [
                    integer-ptr: as [pointer! [integer!]] column/buffer
                    integer/make-in row integer-ptr/value
                ]
                SQL_BIGINT [
                    none/make-in row
                ]
                SQL_BINARY
                SQL_VARBINARY
                SQL_LONGVARBINARY [
                    none/make-in row
                ]
;               SQL_DATE
;               SQL_TYPE_DATE [
;                   date-ptr: as SQL_DATE_STRUCT column/buffer
;
;                   dy: (as integer! date-ptr/year_hi  ) << 8 or (as integer! date-ptr/year_lo  )
;                   dm: (as integer! date-ptr/month_hi ) << 8 or (as integer! date-ptr/month_lo )
;                   dd: (as integer! date-ptr/day_hi   ) << 8 or (as integer! date-ptr/day_lo   )
;
;                   red-date: date/make-in row 0 0 0
;                   date/set-all red-date dy dm dd 0 0 0 0
;
;                   red-date/date: red-date/date and FFFEFFFFh                  ;-- clear time flag
;               ]
                SQL_DATE
                SQL_TYPE_DATE [
                    value: as c-string! column/buffer
                    string/load-in as c-string! column/buffer column/strlen-ind row UTF-8
                ]
;               SQL_TIME
;               SQL_TYPE_TIME [
;                   time-ptr: as SQL_TIME_STRUCT column/buffer
;
;                   th: (as integer! time-ptr/hour_hi  ) << 8 or (as integer! time-ptr/hour_lo  )
;                   tm: (as integer! time-ptr/minute_hi) << 8 or (as integer! time-ptr/minute_lo)
;                   ts: (as integer! time-ptr/second_hi) << 8 or (as integer! time-ptr/second_lo)
;                   tf:  0
;
;                   red-time: time/make-in row 0 0
;                   red-time/time: (3600.0 * as float! th) + (60.0 * as float! tm) + (as float! ts)
;               ]
                SQL_TIME
                SQL_TYPE_TIME [
                    value: as c-string! column/buffer
                    string/load-in as c-string! column/buffer column/strlen-ind row UTF-8
                ]
;               SQL_TIMESTAMP
;               SQL_TYPE_TIMESTAMP [
;                   timestamp-ptr: as SQL_TIMESTAMP_STRUCT column/buffer
;
;                   dy: (as integer! timestamp-ptr/year_hi  ) << 8 or (as integer! timestamp-ptr/year_lo  )
;                   dm: (as integer! timestamp-ptr/month_hi ) << 8 or (as integer! timestamp-ptr/month_lo )
;                   dd: (as integer! timestamp-ptr/day_hi   ) << 8 or (as integer! timestamp-ptr/day_lo   )
;                   th: (as integer! timestamp-ptr/hour_hi  ) << 8 or (as integer! timestamp-ptr/hour_lo  )
;                   tm: (as integer! timestamp-ptr/minute_hi) << 8 or (as integer! timestamp-ptr/minute_lo)
;                   ts: (as integer! timestamp-ptr/second_hi) << 8 or (as integer! timestamp-ptr/second_lo)
;                   tf:  0
;
;                   red-date: date/make-in row 0 0 0
;                   date/set-all red-date dy dm dd th tm ts tf
;               ]
                SQL_TIMESTAMP
                SQL_TYPE_TIMESTAMP [
                    value: as c-string! column/buffer
                    string/load-in as c-string! column/buffer column/strlen-ind row UTF-8
                ]
               ;SQL_INTERVAL_MONTH
               ;SQL_INTERVAL_YEAR
               ;SQL_INTERVAL_YEAR_TO_MONTH
               ;SQL_INTERVAL_DAY
               ;SQL_INTERVAL_HOUR
               ;SQL_INTERVAL_MINUTE
               ;SQL_INTERVAL_SECOND
               ;SQL_INTERVAL_DAY_TO_HOUR
               ;SQL_INTERVAL_DAY_TO_MINUTE
               ;SQL_INTERVAL_DAY_TO_SECOND
               ;SQL_INTERVAL_HOUR_TO_MINUTE
               ;SQL_INTERVAL_HOUR_TO_SECOND
               ;SQL_INTERVAL_MINUTE_TO_SECOND [
               ;    none/make-in row
               ;]
                SQL_GUID [
                    value: as c-string! column/buffer
                    string/load-in as c-string! column/buffer column/strlen-ind >> 1 row UTF-16LE
                ]
                default [
                    integer/make-in row 0
                ]
            ]
        ]


        ;---------------------------------------------------- fetch-statement --
        ;

        fetch-statement: func [
            holder      [red-handle!]
            rows        [red-block!]
            /local
                statement result c row column buffer datatype option
                integer-ptr float-ptr date-ptr year month day buf
        ][
            ODBC_DEBUG ["FETCH-STATEMENT" lf]

            option:    declare sqlsmallint!
            statement: as statement! holder/value

            until [
                result: result-of SQLFetch statement/hstmt

                ODBC_DEBUG ["SQLFetch " result lf]

                switch result [
                    SQL_SUCCESS
                    SQL_SUCCESS_WITH_INFO [
                        row: block/make-in rows statement/columns-cnt

                        column: statement/columns
                        c: 1

                        loop statement/columns-cnt [
                            fetch-column statement/hstmt row column

                            column: column + 1
                            c: c + 1
                        ]
                    ]
                    SQL_ERROR
                    SQL_INVALID_HANDLE
                    SQL_STILL_EXECUTING [
                        SET_RETURN((diagnose-error SQL_HANDLE_STMT statement/hstmt)) exit
                    ]
                    SQL_NO_DATA [
                        ;-- no-op
                    ]
                ]

                result = SQL_NO_DATA
            ]

            ;-- close curser
            ;
            result: result-of SQLCloseCursor statement/hstmt

            ODBC_DEBUG ["SQLCloseCursor " result lf]

            ODBC_REJECT((SQL_ERROR or SQL_INVALID_HANDLE)) [
                SET_RETURN((diagnose-error SQL_HANDLE_STMT statement/hstmt)) exit
            ]

            ;-- close statement
            ;
            SET_INT16(option SQL_CLOSE)
            result: result-of SQLFreeStmt statement/hstmt option

            ODBC_DEBUG ["SQLFreeStmt SQL_CLOSE " result lf]

            ODBC_REJECT((SQL_ERROR or SQL_INVALID_HANDLE)) [
                SET_RETURN((diagnose-error SQL_HANDLE_STMT statement/hstmt)) exit
            ]

            ;-- unbind statement
            ;
            SET_INT16(option SQL_UNBIND)
            result: result-of SQLFreeStmt statement/hstmt option

            ODBC_DEBUG ["SQLFreeStmt SQL_UNBIND " result lf]

            ODBC_REJECT((SQL_ERROR or SQL_INVALID_HANDLE)) [
                SET_RETURN((diagnose-error SQL_HANDLE_STMT statement/hstmt)) exit
            ]

            ;-- reset params
            ;
            SET_INT16(option SQL_RESET_PARAMS)
            result: result-of SQLFreeStmt statement/hstmt option

            ODBC_DEBUG ["SQLFreeStmt SQL_RESET_PARAMS " result lf]

            ODBC_REJECT((SQL_ERROR or SQL_INVALID_HANDLE)) [
                SET_RETURN((diagnose-error SQL_HANDLE_STMT statement/hstmt)) exit
            ]

            SET_RETURN((logic/box true))
        ]


        ;---------------------------------------------------- close-statement --
        ;

        close-statement: func [
            holder    [red-handle!]
            /local
                statement result column
        ][
            ODBC_DEBUG ["CLOSE-STATEMENT" lf]

            statement:  as statement! holder/value
            column:     statement/columns

            loop statement/columns-cnt [
                free-buffer column/buffer
                column: column + 1
            ]

            free-buffer as byte-ptr! statement/columns

            result: result-of SQLFreeHandle SQL_HANDLE_STMT statement/hstmt

            ODBC_DEBUG ["SQLFreeHandle " result lf]

            ODBC_REJECT((SQL_ERROR or SQL_INVALID_HANDLE)) [
                SET_RETURN((diagnose-error SQL_HANDLE_STMT statement/hstmt)) exit
            ]

            free-buffer as byte-ptr! statement

            SET_RETURN((logic/box true))
        ]


        ;--------------------------------------------------- close-connection --
        ;

        close-connection: func [
            holder      [red-handle!]
            /local
                connection result
        ][
            ODBC_DEBUG ["CLOSE-CONNECTION" lf]

            connection: as connection! holder/value

            result: result-of SQLDisconnect connection/hdbc

            ODBC_DEBUG ["SQLDisconnect " result lf]

            ODBC_REJECT((SQL_ERROR or SQL_INVALID_HANDLE or SQL_STILL_EXECUTING)) [
                SET_RETURN((diagnose-error SQL_HANDLE_DBC connection/hdbc)) exit
            ]

            result: result-of SQLFreeHandle SQL_HANDLE_DBC
                                            connection/hdbc

            ODBC_DEBUG ["SQLFreeHandle " result lf]

            ODBC_REJECT((SQL_ERROR or SQL_INVALID_HANDLE)) [
                SET_RETURN((diagnose-error SQL_HANDLE_DBC connection/hdbc)) exit
            ]

            free-buffer as byte-ptr! connection

            SET_RETURN((logic/box true))
        ]


        ;-------------------------------------------------- close-environment --
        ;

        close-environment: func [
            /local
                result
        ][
            ODBC_DEBUG ["CLOSE-ENVIRONMENT" lf]

            result: result-of SQLFreeHandle SQL_HANDLE_ENV environment/henv

            ODBC_DEBUG ["SQLFreeHandle " result lf]

            ODBC_REJECT((SQL_ERROR or SQL_INVALID_HANDLE)) [
                SET_RETURN((diagnose-error SQL_HANDLE_ENV environment/henv)) exit
            ]

            environment/henv: null

            SET_RETURN((logic/box true))
        ]


        ;----------------------------------------------------- diagnose-error --
        ;

        diagnose-error: func [
            type    [integer!]
            holder  [sql-handle!]
            return: [red-block!]
            /local
                result error state native message size length
        ][
            ODBC_DEBUG ["DIAGNOSE-ERROR" lf]

            error:      block/make-in null 5
            state:      allocate 12
            native:     0
            size:       4096
            message:    allocate size
            length:     0

            result: result-of SQLGetDiagRec type
                                            holder
                                            1
                                            state
                                           :native
                                            message
                                            size
                                           :length

            ODBC_DEBUG ["SQLGetDiagRecord " result lf]

            switch result [
                SQL_ERROR
                SQL_INVALID_HANDLE [
                    none/make-in error
                    integer/make-in error 0
                    none/make-in error
                ]
                SQL_SUCCESS
                SQL_SUCCESS_WITH_INFO [
                    string/load-in as c-string! state 5 error UTF-16LE
                    integer/make-in error native
                    string/load-in as c-string! message length error UTF-16LE
                ]
                SQL_NO_DATA []
            ]

            error
        ]

    ]
]


;======================================================================== Red ==
;

context [

    ;--------------------------------------------------------------- routines --
    ;

    _open-environment:   routine [] [odbc/open-environment]

    _list-sources:       routine [sources [block!]] [odbc/list-sources sources]
    _list-drivers:       routine [drivers [block!]] [odbc/list-drivers drivers]

    _open-connection:    routine [dsn [string!]] [odbc/open-connection dsn]

    _open-statement:     routine [connection [handle!]] [odbc/open-statement  connection]
    _translate-statement: routine [connection [handle!] sql     [string!]] [odbc/translate-statement connection sql  ]

    _prepare-statement:  routine [statement  [handle!] sql     [block!]] [odbc/prepare-statement  statement sql    ]
    _execute-statement:  routine [statement  [handle!] sql     [block!]] [odbc/execute-statement  statement sql    ]
    _describe-statement: routine [statement  [handle!] columns [block!]] [odbc/describe-statement statement columns]
    _fetch-statement:    routine [statement  [handle!] rows    [block!]] [odbc/fetch-statement    statement rows   ]
    _catalog-statement:  routine [statement  [handle!] catalog [block!]] [odbc/catalog-statement  statement catalog]

    _close-statement:    routine [statement  [handle!]] [odbc/close-statement  statement ]

    _close-connection:   routine [connection [handle!]] [odbc/close-connection connection]

    _close-environment:  routine [] [odbc/close-environment]


    ;------------------------------------------------------------ environment --
    ;

    environment: object [
        handle:      none
        connections: []
    ]


    ;----------------------------------------------------------------- protos --
    ;

    connection-proto: object [
        type:      'connection
        handle:     none
        statements: []
    ]

    statement-proto: object [
        type:      'statement
        handle:     none
        connection: none
        sql:        none
    ]

    ;------------------------------------------------------------------- init --
    ;

    set 'odbc-init function [
        "Init ODBC environment."
    ][
        result: _open-environment

        unless handle? result [
            cause-error 'user 'message reduce [rejoin ["cannot init environment: " mold result]]
        ]

        environment/handle: result
    ]

    odbc-init

    ;------------------------------------------------------------------- open --
    ;

    set 'odbc-open function [
        "Connect to a datasource."
        datasource [string!] "connection string"
    ][
        odbc-init

        result: _open-connection datasource

        unless handle? result [
            cause-error 'user 'message reduce [rejoin [{cannot connect "} datasource {": } mold result]]
        ]

        connection: make connection-proto [
            handle: result
        ]

        append environment/connections connection

        connection
    ]


    ;------------------------------------------------------------------ first --
    ;

    set 'odbc-first function [
        "Returns an ODBC statement."
        connection [object!]
    ][
        result: _open-statement connection/handle

        unless handle? result [
            cause-error 'user 'message reduce [rejoin ["cannot allocate statement: " mold result]]
        ]

        statement: make statement-proto compose [
            handle:      result
            connection: (connection)
            sql:         none
        ]

        append connection/statements statement

        statement
    ]


    ;---------------------------------------------------------------- sources --
    ;

    set 'odbc-sources function [
        "Returns block of ODBC datasource/description pairs"
    ][
        odbc-init

        result: _list-sources sources: copy []

        if block? result [
            cause-error 'user 'message reduce [rejoin ["cannot list sources: " mold result]]
        ]

        odbc-free

        new-line/skip/all sources on 2
    ]


    ;---------------------------------------------------------------- drivers --
    ;

    set 'odbc-drivers function [
        "Returns block of ODBC driver-description/attributes pairs"
        /local desc attrs attr
    ][
        odbc-init

        result: _list-drivers drivers: copy []

        if block? result [
            cause-error 'user 'message reduce [rejoin ["cannot list drivers: " mold result]]
        ]

        drivers: collect [foreach [desc attrs] drivers [
            attrs: split head remove back tail attrs #"^@"
            attrs: collect [foreach attr attrs [
                pair: split attr #"="
                keep to word! first pair
                keep second pair
            ]]

            keep reduce [desc attrs]
        ]]

        odbc-free

        new-line/skip/all drivers on 2
    ]


    ;-------------------------------------------------------------- translate --
    ;

    set 'odbc-translate function [
        "Translates SQL statement into native SQL."
        connection [object!]
        sql [string!]
    ][
        unless any [in connection 'type connection/type = 'connection] [
            cause-error 'script 'invalid-arg [entity]
        ]

        result: _translate-statement connection/handle sql

        if block? result [
            cause-error 'user 'message reduce [rejoin ["cannot translate statement " mold first query ": " mold result]]
        ]

        translation: result
    ]


    ;----------------------------------------------------------------- insert --
    ;

    set 'odbc-insert function [
        "Executes SQL statement."
        statement [object!]
        sql [string! word! block!] "statement w/o parameter(s) (block gets reduced) or TABLES, COLUMNS or TYPES catalog"
        /local
            column
    ][
        query: reduce either block? sql [sql] [[sql]]                           ;-- block argument

        unless parse query [[string! | 'tables | 'columns | 'types] to end] [
            cause-error 'script 'invalid-arg [sql]
        ]

        switch type?/word value: first query [
            word! [ ;-- catalog --
                result: _catalog-statement statement/handle query

                if block? result [
                    cause-error 'user 'message reduce [rejoin ["cannot catalog " mold first query ": " mold result]]
                ]

                result: _describe-statement statement/handle data: copy []

                if block? result [
                    cause-error 'user 'message reduce [rejoin ["cannot describe statement " mold first query ": " mold result]]
                ]
            ]

            string! [ ;-- statement --
                unless same? statement/sql value [                              ;-- prepare new statement
                    result: _prepare-statement statement/handle query

                    if block? result [
                        cause-error 'user 'message reduce [rejoin ["cannot prepare statement " mold first query ": " mold result]]
                    ]

                    statement/sql: value
                ]

                result: _execute-statement statement/handle query

                if block? result [
                    cause-error 'user 'message reduce [rejoin ["cannot execute statement " mold first query ": " mold result]]
                ]

                result: _describe-statement statement/handle data: copy []

                if block? result [
                    cause-error 'user 'message reduce [rejoin ["cannot describe statement " mold first query ": " mold result]]
                ]
            ]
        ]

        either integer? rows: first data [
            rows                                                                ;-- number of affected rows
        ][
            collect [foreach column data [keep to word! column]]                ;-- column titles
        ]
    ]


    ;------------------------------------------------------------------- copy --
    ;

    set 'odbc-copy function [
        "Copy data from executed SQL statement."
        statement [object!]
        /part "Limit the rows returned."
            length [integer!]
    ][
        if part [
            cause-error 'user 'message ["Not implemented yet."]
        ]

		result: _fetch-statement statement/handle rows: copy []

        if block? result [
            cause-error 'user 'message reduce [rejoin ["cannot fetch statement " mold sql ": " mold result]]
        ]

        new-line/all rows on
    ]


    ;------------------------------------------------------------------ close --
    ;

    set 'odbc-close function [
        "Close connection or statement."
        entity [object!] "connection or statement handle"
    ][
        unless in entity 'type [
            cause-error 'script 'invalid-arg [entity]
        ]

        switch entity/type [
            connection [
                connection: entity

                while [not tail? connection/statements] [
                    odbc-close take connection/statements
                ]

                result: _close-connection connection/handle

                if block? result [
                    cause-error 'user 'message reduce [rejoin ["cannot close connection: " mold result]]
                ]

                odbc-free

                clear connection/statements
            ]
            statement [
                statement: entity

                result: _close-statement statement/handle

                if block? result [
                    cause-error 'user 'message reduce [rejoin ["cannot close statement: " mold result]]
                ]

                statement/connection: none
            ]
        ]

        entity/handle: none
        entity
    ]


    ;------------------------------------------------------------------ close --
    ;

    set 'odbc-free function [
        "Close environment."
    ][
        result: _close-environment

        if block? result [
            cause-error 'user 'message reduce [rejoin ["cannot free environment: " mold result]]
        ]

        environment/handle: none
    ]

]

