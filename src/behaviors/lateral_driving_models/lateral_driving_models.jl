export
        LateralDriverModel,
        ProportionalLaneTracker

abstract LateralDriverModel
get_name(::LateralDriverModel) = "???"
reset_hidden_state!(model::LateralDriverModel) = model # do nothing by default
observe!(model::LateralDriverModel, scene::Scene, roadway::Roadway, egoid::Int) = model  # do nothing by default
Base.rand(model::LateralDriverModel) = error("rand not implemented for model $model")
Distributions.pdf(model::LateralDriverModel, a_lon::Float64) = error("pdf not implemented for model $model")
Distributions.logpdf(model::LateralDriverModel, a_lon::Float64) = error("logpdf not implemented for model $model")

type ProportionalLaneTracker <: LateralDriverModel
    a::Float64 # predicted acceleration
    σ::Float64 # optional stdev on top of the model, set to zero or NaN for deterministic behavior
    kp::Float64 # proportional constant for lane tracking
    kd::Float64 # derivative constant for lane tracking

    function ProportionalLaneTracker(;
        σ::Float64 = NaN,
        kp::Float64 = 1.0,
        kd::Float64 = 0.1,
        )

        retval = new()
        retval.a = NaN
        retval.σ = σ
        retval.kp = kp
        retval.kd = kd
        retval
    end
end
get_name(::ProportionalLaneTracker) = "ProportionalLaneTracker"
function observe!(model::ProportionalLaneTracker, scene::Scene, roadway::Roadway, egoid::Int)

    ego_index = get_index_of_first_vehicle_with_id(scene, egoid)
    veh_ego = scene[ego_index]
    t = veh_ego.state.posF.t # lane offset
    dt = veh_ego.state.v * sin(veh_ego.state.posF.ϕ) # rate of change of lane offset
    model.a = -t*model.kp - dt*model.kd

    model
end
function Base.rand(model::ProportionalLaneTracker)
    if isnan(model.σ) || model.σ ≤ 0.0
        model.a
    else
        rand(Normal(model.a, model.σ))
    end
end
function Distributions.pdf(model::ProportionalLaneTracker, a_lat::Float64)
    if isnan(model.σ) || model.σ ≤ 0.0
        Inf
    else
        pdf(Normal(model.a, model.σ), a_lon)
    end
end
function Distributions.logpdf(model::ProportionalLaneTracker, a_lat::Float64)
    if isnan(model.σ) || model.σ ≤ 0.0
        Inf
    else
        logpdf(Normal(model.a, model.σ), a_lon)
    end
end

