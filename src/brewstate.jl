# The state of the brew of a session, and the warnings collected while brewing.

"""
    AbstractBrewStatus

The state of the brew of a [`Session`](@ref): [`Brewed`](@ref) or [`BrewFailed`](@ref).
"""
abstract type AbstractBrewStatus end

"""
    Brewed()

The quiver of the session brews: its result is up to date.
"""
struct Brewed <: AbstractBrewStatus end

"""
    BrewFailed(exception)

The quiver of the session does not brew (e.g. a transfer takes more than there is), with
the `exception` thrown by the brew. A session is in this state only when its quiver was
loaded so; edits that would make a brewing quiver fail are refused.
"""
struct BrewFailed <: AbstractBrewStatus
    exception::Exception
end

"""
    isbrewed(status_or_session)

Whether the brew is up to date.
"""
isbrewed(::Brewed) = true
isbrewed(::BrewFailed) = false

Base.show(io::IO, ::Brewed) = print(io, "Brewed()")
Base.show(io::IO, f::BrewFailed) = print(io, "BrewFailed(", _message(f.exception), ")")

# a one-line message of an exception
_message(e::Exception) = sprint(showerror, e)
_message(e::ArgumentError) = e.msg

"""
    BrewWarning(node, message)

A warning about the brew of a session: about the node `node` (e.g. its contents exceed the
capacity of its vessel), or about the whole quiver when `node` is `nothing` (e.g. what the
import of a recipe could not read).
"""
struct BrewWarning
    node::Union{Nothing, Symbol}
    message::String
end

# a logger collecting the warnings (and errors) logged while running a function, so that
# the engine's `@warn`s reach the interfaces instead of the terminal
struct CollectingLogger <: AbstractLogger
    messages::Vector{String}
end
Logging.min_enabled_level(::CollectingLogger) = Warn
Logging.shouldlog(::CollectingLogger, args...) = true
Logging.catch_exceptions(::CollectingLogger) = true
function Logging.handle_message(l::CollectingLogger, level, message, args...; kwargs...)
    push!(l.messages, string(message))
    return nothing
end

# the value of `f()` and the messages it logged
function collecting(f)
    l = CollectingLogger(String[])
    value = with_logger(f, l)
    return value, l.messages
end
