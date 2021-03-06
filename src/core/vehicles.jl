immutable Frenet
    roadind::RoadIndex
    s::Float64 # distance along lane
    t::Float64 # lane offset, positive is to left
    ϕ::Float64 # lane relative heading
end
function Frenet(roadproj::RoadProjection, roadway::Roadway)
    roadind = RoadIndex(roadproj.curveproj.ind, roadproj.tag)
    s = roadway[roadind].s
    t = roadproj.curveproj.t
    ϕ = _mod2pi2(roadproj.curveproj.ϕ)
    Frenet(roadind, s, t, ϕ)
end
Frenet(posG::VecSE2, roadway::Roadway) = Frenet(proj(posG, roadway), roadway)

function get_posG(frenet::Frenet, roadway::Roadway)
    curvept = roadway[frenet.roadind]
    pos = curvept.pos + polar(frenet.t, curvept.pos.θ + π/2)
    VecSE2(pos.x, pos.y, frenet.ϕ + curvept.pos.θ)
end

const NULL_FRENET = Frenet(NULL_ROADINDEX, NaN, NaN, NaN)

Base.show(io::IO, frenet::Frenet) = print(io, "Frenet(", frenet.roadind, @sprintf(", %.3f, %.3f, %.3f)", frenet.s, frenet.t, frenet.ϕ))
function Base.isapprox(a::Frenet, b::Frenet;
    rtol::Real=cbrt(eps(Float64)),
    atol::Real=sqrt(eps(Float64))
    )

    a.roadind.tag == b.roadind.tag &&
    isapprox(a.roadind.ind.t, b.roadind.ind.t, atol=atol, rtol=rtol) &&
    isapprox(a.s, b.s, atol=atol, rtol=rtol) &&
    isapprox(a.t, b.t, atol=atol, rtol=rtol) &&
    isapprox(a.ϕ, b.ϕ, atol=atol, rtol=rtol)
end


immutable VehicleState
    posG::VecSE2 # global
    posF::Frenet # lane-relative frame
    v::Float64

    VehicleState() = new(VecSE2(), NULL_FRENET, NaN)
    VehicleState(posG::VecSE2, v::Float64) = new(posG, NULL_FRENET, v)
    VehicleState(posG::VecSE2, posF::Frenet, v::Float64) = new(posG, posF, v)
    VehicleState(posG::VecSE2, roadway::Roadway, v::Float64) = new(posG, Frenet(posG, roadway), v)
    VehicleState(posF::Frenet, roadway::Roadway, v::Float64) = new(get_posG(posF, roadway), posF, v)
end
Base.show(io::IO, s::VehicleState) = print(io, "VehicleState(", s.posG, ", ", s.posF, ", ", @sprintf("%.3f", s.v), ")")
function Vec.lerp(a::VehicleState, b::VehicleState, t::Float64, roadway::Roadway)
    posG = lerp(a.posG, b.posG, t)
    v = lerp(a.v, b.v, t)
    VehicleState(posG, roadway, v)
end

baremodule AgentClass
    const CAR        = 1
    const MOTORCYCLE = 2
    const TRUCK      = 3
end

immutable VehicleDef
    id::Int
    class::Int # ∈ AgentClass
    length::Float64
    width::Float64
end
const NULL_VEHICLEDEF = VehicleDef(0, AgentClass.CAR, NaN, NaN)
Base.show(io::IO, d::VehicleDef) = @printf(io, "VehicleDef(%d, %s, %.3f, %.3f)", d.id, d.class == AgentClass.CAR ? "CAR" : d.class == AgentClass.MOTORCYCLE ? "MOTORCYCLE" : "TRUCK", d.length, d.width)

type Vehicle
    state::VehicleState # position is at the center
    def::VehicleDef

    function Vehicle(
        state::VehicleState=VehicleState(),
        def::VehicleDef=NULL_VEHICLEDEF,
        )
        new(state,def)
    end
end
Base.show(io::IO, v::Vehicle) = print(io, "Vehicle(", v.state, ", ", v.def, ")")
function Base.copy!(veh1::Vehicle, veh2::Vehicle)
    veh1.state = veh2.state
    veh1.def = veh2.def
    veh1
end

get_vel_s(s::VehicleState) = s.v * cos(s.posF.ϕ) # velocity along the lane
get_vel_t(s::VehicleState) = s.v * sin(s.posF.ϕ) # velocity ⟂ to lane

get_footpoint(veh::Vehicle) = veh.state.posG + polar(veh.state.posF.t, veh.state.posG.θ-veh.state.posF.ϕ-π/2)