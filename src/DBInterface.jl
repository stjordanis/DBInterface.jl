module DBInterface

"Database packages should subtype `DBInterface.Connection` which represents a connection to a database"
abstract type Connection end

"""
    DBInterface.connect(DB, args...; kw...) => DBInterface.Connection

Database packages should overload `DBInterface.connect` for a specific `DB` `DBInterface.Connection` subtype
that returns a valid, live database connection that can be queried against.
"""
function connect end

connect(T, args...; kw...) = throw(NotImplementedError("`DBInterface.connect` not implemented for `$T`"))

"""
    DBInterface.close!(conn::DBInterface.Connection)

Immediately closes a database connection so further queries cannot be processed.
"""
function close! end

close!(conn::Connection) = throw(NotImplementedError("`DBInterface.close!` not implemented for `$(typeof(conn))`"))

"Database packages should provide a `DBInterface.Statement` subtype which represents a valid, prepared SQL statement that can be executed repeatedly"
abstract type Statement end

"""
    DBInterface.prepare(conn::DBInterface.Connection, sql::AbstractString) => DBInterface.Statement
    DBInterface.prepare(f::Function, sql::AbstractString) => DBInterface.Statement

Database packages should overload `DBInterface.prepare` for a specific `DBInterface.Connection` subtype, that validates and prepares
a SQL statement given as an `AbstractString` `sql` argument, and returns a `DBInterface.Statement` subtype. It is expected
that `DBInterface.Statement`s are only valid for the lifetime of the `DBInterface.Connection` object against which they are prepared.
For convenience, users may call `DBInterface.prepare(f::Function, sql)` which first calls `f()` to retrieve a valid `DBInterface.Connection`
before calling `DBInterface.prepare(conn, sql)`; this allows deferring connection retrieval and thus statement preparation until runtime,
which is often convenient when building applications.
"""
function prepare end

prepare(conn::Connection, sql::AbstractString) = throw(NotImplementedError("`DBInterface.prepare` not implemented for `$(typeof(conn))`"))
prepare(f::Function, sql::AbstractString) = prepare(f(), sql)

const PREPARED_STMTS = Dict{Symbol, Statement}()

"""
    DBInterface.@prepare f sql

Takes a `DBInterface.Connection`-retrieval function `f` and SQL statement `sql` and will return a prepared statement, via usage of `DBInterface.prepare`.
If the statement has already been prepared, it will be re-used (prepared statements are cached).
"""
macro prepare(getDB, sql)
    key = gensym()
    return quote
        get!(DBInterface.PREPARED_STMTS, $(QuoteNode(key))) do
            DBInterface.prepare($(esc(getDB)), $sql)
        end
    end
end

"Any object that iterates \"rows\", which are objects that are property-accessible and indexable. See `DBInterface.execute` for more details on fetching query results."
abstract type Cursor end

"""
    DBInterface.execute(conn::DBInterface.Connection, sql::AbstractString, [params]) => DBInterface.Cursor
    DBInterface.execute(stmt::DBInterface.Statement, [params]) => DBInterface.Cursor

Database packages should overload `DBInterface.execute` for a valid, prepared `DBInterface.Statement` subtype (the first method
signature is defined in DBInterface.jl using `DBInterface.prepare`), which takes an optional `params` argument, which should be
an indexable collection (`Vector` or `Tuple`) for positional parameters, or a `NamedTuple` for named parameters.
`DBInterface.execute` should return a valid `DBInterface.Cursor` object, which is any iterator of "rows",
which themselves must be property-accessible (i.e. implement `propertynames` and `getproperty` for value access by name),
and indexable (i.e. implement `length` and `getindex` for value access by index). These "result" objects do not need
to subtype `DBInterface.Cursor` explicitly as long as they satisfy the interface. For DDL/DML SQL statements, which typically
do not return results, an iterator is still expected to be returned that just iterates `nothing`, i.e. an "empty" iterator.
"""
function execute end

execute(stmt::Statement, params=()) = throw(NotImplementedError("`DBInterface.execute` not implemented for `$(typeof(stmt))`"))

execute(conn::Connection, sql::AbstractString, params=()) = execute(prepare(conn, sql), params)

struct LazyIndex{T} <: AbstractVector{Any}
    x::T
    i::Int
end

Base.IndexStyle(::Type{<:LazyIndex}) = Base.IndexLinear()
Base.IteratorSize(::Type{<:LazyIndex}) = Base.HasLength()
Base.size(x::LazyIndex) = (length(x.x),)
Base.getindex(x::LazyIndex, i::Int) = x.x[i][x.i]

"""
    DBInterface.executemany(conn::DBInterface.Connect, sql::AbstractString, [params]) => Nothing
    DBInterface.executemany(stmt::DBInterface.Statement, [params]) => Nothing

Similar in usage to `DBInterface.execute`, but allows passing multiple sets of parameters to be executed in sequence.
`params`, like for `DBInterface.execute`, should be an indexable collection (`Vector` or `Tuple`) or `NamedTuple`, but instead
of a single scalar value per parameter, an indexable collection should be passed for each parameter. By default, each set of
parameters will be looped over and `DBInterface.execute` will be called for each. Note that no result sets or cursors are returned
for any execution, so the usage is mainly intended for bulk INSERT statements.
"""
function executemany(stmt::Statement, params=())
    if !isempty(params)
        param = params[1]
        len = length(param)
        all(x -> length(x) == len, params) || throw(ParameterError("parameters provided to `DBInterface.executemany!` do not all have the same number of parameters"))
        for i = 1:len
            xargs = LazyIndex(params, i)
            execute(stmt, xargs)
        end
    else
        execute(stmt)
    end
    return
end

executemany(conn::Connection, sql::AbstractString, params=()) = executemany(prepare(conn, sql), params)

"""
    DBInterface.close!(stmt::DBInterface.Statement)

Close a prepared statement so further queries cannot be executed.
"""
close!(stmt::Statement) = throw(NotImplementedError("`DBInterface.close!` not implemented for `$(typeof(stmt))`"))

"""
    DBInterface.lastrowid(x::Cursor) => Int

If supported by the specific database cursor, returns the last inserted row id after executing an INSERT statement.
"""
lastrowid(::T) where {T} = throw(NotImplementedError("`DBInterface.lastrowid` not implemented for $T"))

"""
    DBInterface.close!(x::Cursor) => Nothing

Immediately close a resultset cursor. Database packages should overload for the provided resultset `Cursor` object.
"""
close!(x) = throw(NotImplementedError("`DBInterface.close!` not implemented for `$(typeof(x))`"))

# exception handling
"Error for signaling a database package hasn't implemented an interface method"
struct NotImplementedError <: Exception
    msg::String
end

"Error for signaling that parameters are used inconsistently or incorrectly."
struct ParameterError <: Exception
    msg::String
end

"Standard warning object for various database operations"
struct Warning
    msg::String
end

"Fallback, generic error object for database operations"
struct Error <: Exception
    msg::String
end

end # module
