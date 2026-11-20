# The models of BrewingFormulas a session brews with, chosen by an undoable command.

"""
    MODEL_CHOICES

The models of BrewingFormulas a session can brew with, by kind, the first being the
default (see `DEFAULT_MODELS`): `bitterness` (Tinseth, Rager), `color` (Morey, Daniels,
Mosher, Druey-Daniels, Druey-Noonan), `abv` (Balling, simple) and `gravity` (the
equivalence between sugar content and specific gravity).
"""
const MODEL_CHOICES = (
    bitterness = Any[Tinseth(), Rager()],
    color = Any[Morey(), Daniels(), Mosher(), DrueyDaniels(), DrueyNoonan()],
    abv = Any[Balling(), SimpleABV()],
    gravity = Any[SugarGravityQuad(), SugarGravity()])

# the supertype of the models of each kind
const _MODEL_TYPES = (bitterness = BitternessModel, color = ColorModel, abv = ABVModel,
                      gravity = Union{SugarGravity, SugarGravityQuad}, refractometer = RefractometerModel)

"""
    SetModels(models::NamedTuple)

Brews the session with the `models` of BrewingFormulas (overriding `DEFAULT_MODELS`; see
[`MODEL_CHOICES`](@ref)), e.g. `SetModels((bitterness = Rager(),))`. The models are not part
of the quiver, but of the session: the whole quiver is brewed again with them. Reverted by
its [`Inverse`](@ref).
"""
struct SetModels <: EditCommand
    models::NamedTuple
end

_model_name(m) = string(nameof(typeof(m)))
describe(c::SetModels) = isempty(c.models) ? "Use the default models" :
    "Use the models " * join(("$k $(_model_name(m))" for (k, m) in pairs(c.models)), ", ")
function validate(c::SetModels, q::Quiver)
    for (k, m) in pairs(c.models)
        haskey(_MODEL_TYPES, k) || _refuse(c, "there are no models of $k: " * join(keys(_MODEL_TYPES), ", "))
        m isa _MODEL_TYPES[k] || _refuse(c, "$(_model_name(m)) is not a model of $k")
    end
end
affected(::SetModels, ::Quiver) = AllNodes()
revert_record(c::SetModels, q::Quiver) =
    throw(ArgumentError("the models are those of a session: apply SetModels to a session"))
_revert_record(s::Session, c::SetModels) = Inverse(SetModels(s.models))
perform!(s, c::SetModels) = (s.models = c.models; nothing)

"""
    models_in_use(s::Session)

The models the session brews with: `DEFAULT_MODELS` with those of the session.
"""
models_in_use(s::Session) = merge(DEFAULT_MODELS, s.models)

"""
    set_model(s::Session, kind, model) -> SetModels

The command that brews the session with `model` for `kind` (e.g. `:bitterness`), keeping its
other models.
"""
set_model(s::Session, kind::Symbol, model) = SetModels(merge(s.models, NamedTuple{(kind,)}((model,))))
