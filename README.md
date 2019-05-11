# Red-ODBC
ODBC binding for Red and Red/System

---

:warning: The Red language doesn't do modules and ports right now. 
The ODBC binding therefor implements an API based on simple functions, but is
going to change when ports are available!

---

The Red and Red/System ODBC binding allows easy access to databases and data 
sources supporting ODBC.

The binding supports SQL statements `SELECT` and `INSERT`, `UPDATE` and
`DELETE` as well as *catalog functions* for tables, columns and types. It
supports *statement parameters* and is Unicode aware. It supports
*prepared execution* of statements.

The binding is currently available only for the Windows platform, other 
platforms may follow. So far it has been tested with MySQL, PostgreSQL and
Intersystems Caché as well as the Microsoft Text Driver. Of course it's
supposed to work with any ODBC data source.

# Usage
To use the ODBC binding, `%odbc.reds` and `%odbc.red` have to be located in a
suitable place. They are imported with

```Red
#import %odbc.red
```

Scripts using the ODBC binding need to be compiled, because the Red ODBC binding
is partly written in Red/system.

# ODBC drivers and datasources

## Drivers
Information on installed ODBC drivers is accessible with

```Red
drivers: odbc-drivers
```

as a block of description/attributes pairs.

## Datasources
Information on configured system and user ODBC datasources is accessible with

```Red
sources: odbc-sources
```

as a block of datasource name and description pairs.

# ODBC Connections and Statements

## Opening Connections
If a datasource `<DATASOURCE>` has been set up in the systems ODBC panel,
opening a connection with `ODBC-OPEN` is as easy as

```Red
connection: odbc-open "<DATASOURCE>"
```

Alternatively a connection string can be supplied

```Red
connection: odbc-open "driver={<DRIVERNAME>};server=<IPADDRESS>;port=<PORT>;database=<DATABASE>;uid=<USER>;pwd=<PASS>"
```

with a target string tailored to the specific requirements of the database
one is using.

## Opening Statements
After a connection to a database is established, one or more statement handlers
haves to be allocated with the `ODBC-FIRST` function:

```Red
statement: odbc-first connection
```

One may allocate multiple statements on the same database connection:

```Red
customers: odbc-first warehouse-connection
products:  odbc-first warehouse-connection
orders:    odbc-first warehouse-connection
```

There are benefits in using multiple statements for specialised purposes
depending on your usage patterns (see the section on statement preparation
for further information).

## Closing Statements and Connections
Closing a statement is done with `ODBC-CLOSE`:

```Red
odbc-close statement
```

Closing a connection - along with all associated statements - is done using
`ODBC-CLOSE`, too:

```Red
odbc-close connection
```

Because closing a connections automatically closes all statements associated
with this connection, it is sufficient to just close the connection.

# Executing SQL Statements

## Inserting Statements, retrieving results
The following examples should give an (informal) idea on how SQL statements are executed. Here's is a trivial SELECT statement:

```Red
odbc-insert statement "select * from Cinema.Film"
== [ID Category Description Length PlayingNow Rating TicketsSold Title]
odbc-copy statement
== [
    [1 1 {A post-modern excursion into family dynamics and Thai cuisine.} 130 true "PG-13" 47000 "ÄÖÜßäöü"]
    [2 1 "A gripping true story of honor and discovery" 122 true "R" 50000 "A Kung Fu Hangman1"]
    [3 1 "A Jungian analysis of pirates and honor" 101 true "PG" 5000 "A Kung Fu Hangman"]
    [4 1 "A charming diorama about sibling rivalry" 124 true "G" 7000 "Holy Cooking"]
    [5 2 "An exciting diorama of struggle in Silicon Valley" 100 true "PG" 48000 "The Low Calorie Guide to the Internet"]
    [6 2 "A heart-w...
```

A parametrized SELECT statement:

```Red
odbc-insert statement ["select * from Cinema.Film where ID = ?" 6]
== [ID Category Description Length PlayingNow Rating TicketsSold Title]
odbc-copy statement
== [[6 2 "A heart-warming tale of friendship" 91 true "G" 7500 "Gangs of New York"]]
```

A INSERT statement inserting one row:

```Red
odbc-insert statement ["insert into Persons (Name, Age) values (?, ?)" person/name person/age]
== 1
```

A UPDATE statement updating no rows at all:

```Red
odbc-insert statement ["update Persons set Name = ? where ID = ?" "nobody" 0]
== 0
```

A DELETE statement deleting five rows:

```Red
odbc-insert statement ["delete from Subscribers where Subscription = ?" cancel]
== 5
```

## Affected rows
With row-changing INSERT/UPDATE/DELETE statements, `odbc-insert` simply returns the number of rows affected by the statement:

```Red
odbc-insert statement ["insert into Persons (Name, Age) values (?, ?)" person/name person/age]
== 1
```

## Retrieving result sets
With SELECT statements, `odbc-insert` returns a block of column names as Red words (see below), on `odbc-copy` you retrieve the actual rows:

```Red
odbc-insert statement ["select LastName, FirstName from persons"]
== [LastName FirstName]
odbc-copy statement
== [
    ["Acre" "Anton"]
    ["Bender" "Bill"]
    ...
```

When you have to work with large result sets, you may want to retrieve results in portions of *n* rows a time using refined `odbc-copy/part`:

```Red
odbc-insert statement ["select LastName, FirstName from persons"]
== [LastName FirstName]
odbc-copy/part statement 2
== [
    ["Anderson" "Anton"]
    ["Brown" "Bill"]
]
odbc-copy/part statement 2
== [
    ["Clark" "Christopher"]
    ["Denver" "Dick"]
]
odbc-copy/part statement 2
== [
    ["Evans" "Endo"]
    ["Flores" "Fridolin"]
]
...
```

## Column names

For SELECT statements and catalog functions (see below) `odbc-insert` returns 
a block of column names as Red words, while `odbc-copy` retrieves the actual
results of the statement.

Using the column names returned it's easy to keep your rebol code in sync with
your SQL statements:

```Red
columns: odbc-insert statement ["select ID, Category, Title from Cinema.Film"]
== [ID Category Title]
foreach :columns odbc-copy statement [print [id category title]]
1 1 ÄÖÜßäöü
2 1 A Kung Fu Hangman1
3 1 A Kung Fu Hangman
4 1 Holy Cooking
5 2 The Low Calorie Guide to the Internet
...
```

If, for some reason, you later change your SQL statement to something like

```Red
columns: odbc-insert statement ["select ID, Descriptions, Title, Length, Category from cinema.film"]
== [ID Description Title Length Category]
```

this will work without modifications with the same retrieval code as above,
requiring no changes at all:

```Red
foreach :columns odbc-copy statement [print [id category title]]
== 1 1 ÄÖÜßäöü
2 1 A Kung Fu Hangman1
3 1 A Kung Fu Hangman
4 1 Holy Cooking
5 2 The Low Calorie Guide to the Internet
```

The column names are generated directly from the result set's column
description and made available as normal Red words.

## Prepared Statements
Often, you'll find yourself executing the same SQL statements again and again. 
The ODBC extension supports this by preparing statements for later reuse (i.e.
execution), which saves the ODBC driver and your database the effort to parse
the SQL and to determine an access plan every single time. Instead, a 
previously prepared statement is reused and no statement string needs to be 
transfered to the database.

To prepare a statements, just `odbc-insert` a SQL string, likely along with 
parameter markers `?` and parameters. If later you `odbc-insert` the same
SQL string along with that statement, internally the statement is only 
excecuted, but not prepared again.

Successive calls to `odbc-insert` then supply the same SQL, paramaters, 
however, may of course differ:

```Red
statement: first database: open odbc://mydatabase
sql: "select * from Table where Value = ?"
odbc-insert statement [sql 1]
odbc-copy statement
odbc-insert statement [sql 2]
odbc-copy statement
odbc-insert statement [sql 3]
odbc-copy statement
odbc-close database
```

The more complex your statement is, the more noticable the speed gain
achievable with prepared statements should get.

Whether a SQL string supplied needs to be prepared before execution or whether
it can be excecuted right away, is determined by the SAME?-ness of the SQL
strings supplied:

```Red
statement: first database: open odbc://mydatabase
products:  "select * from product  where product_id  = ?"
customers: "select * from customer where customer_id = ?"
odbc-insert db [products  1] ;-  preparation and execution
odbc-insert db [products  2] ;-- execution only
odbc-insert db [customers 3] ;-- preparation and execution
odbc-insert db [customers 4] ;-- execution only
odbc-insert db [products  1] ;-- again, preparation and execution
```

## Statement Parameters
You may already have noticed the use of statement parameters. To use them, 
instead of just supplying a statement string supply a block to `odbc-insert`.
The statement string has to be the first item in the block, let parameters 
follow as applicable:

```Red
odbc-insert statement ["select ? from Sample.Table where ID = ?" "Test" 2]
odbc-copy statement
== [["Test"]]
```

Note that the block supplied will be reduced automatically:

```Red
set [name age] ["Homer Simpson" 49]
odbc-insert statement ["insert into Persons (Name, Age) values (?, ?)" name age]
odbc-copy statement
== 1
```

The datatypes supported so far are:

- integer!
- string!
- :soon: binary!
- :soon: logic!
- :soon: time!
- :soon: date!

## Datatype Conversions
If the built in automatic type conversion for data retrieval doesn't fit your
needs, you may cast values to different types in your SQL statement:

```Red
odbc-insert statement ["select 1 * ID from Sample.Person where ID = 1"]
type? first copy db
== decimal!
odbc-insert statement ["select cast (1 * ID as integer) from Sample.Person where ID = 1"]
type? first copy db
== integer!
```

Statement parameters inserted into the result columns will always be returned
as strings unless told otherwise:

```Red
odbc-insert statement ["select ? from Sample.Person where ID = 1" 1]
type? first copy db
== string!
odbc-insert statement ["select cast (? as integer) from Sample.Person where ID = ?" 1]
type? first copy db
== integer!
```

If there is no applicable Red datatype to contain a SQL value, the value will
be returned as a string.


# Catalog functions

## Tables
Information about the tables in a database is available with

```Red
odbc-insert statement 'tables
```

## Columns
Information about the columns in a database is available with

```Red
odbc-insert statement 'columns
```

## Types
Information about the types used by the database is available with

```Red
odbc-insert statement 'types
```

