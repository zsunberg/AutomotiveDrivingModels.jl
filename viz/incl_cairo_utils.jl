using AutomotiveDrivingModels

using Cairo
using Reel
using Interact

# include(Pkg.dir("AutomotiveDrivingModels", "viz", "Renderer.jl")); using .Renderer
# include(Pkg.dir("AutomotiveDrivingModels", "viz", "ColorScheme.jl")); using .ColorScheme

import Graphs: edges, num_vertices, vertices

colorscheme = getcolorscheme("monokai")

function render_car!(
    rm::RenderModel,
    car::Vehicle,
    color :: Colorant = RGB(rand(), rand(), rand())
    )

    add_instruction!(rm, render_car, (car.pos.x, car.pos.y, car.pos.ϕ, color))
    rm
end

function render_trace!(
    rm::RenderModel,
    pdset::PrimaryDataset,
    carid::Integer,
    validfind_start::Int,
    validfind_end::Int;
    color::Colorant=RGB(0xBB,0xBB,0xFF),
    linewidth::Float64=0.25, # [m]
    arrowhead_len::Float64=1.0 # [m]
    )

    

    npts = validfind_end - validfind_start + 1
    pts = Array(Float64, 2, npts)
    pt_index = 0

    for validfind in validfind_start:validfind_end

        if validfind2frameind(pdset, validfind) != 0
            carind = carid2ind_or_negative_two_otherwise(pdset, carid, validfind)
            if carind != -2
                pt_index += 1
                pts[1,pt_index] = get(pdset, :posGx, carind, validfind)
                pts[2,pt_index] = get(pdset, :posGy, carind, validfind)
            end
        end
    end

    pts = pts[:,1:pt_index]

    add_instruction!(rm, render_arrow, (pts, color, linewidth, arrowhead_len))
    # add_instruction!(rm, render_point_trail, (pts, color))
end

Renderer.camera_set_pos!(rm::RenderModel, car::Vehicle) = camera_set_pos!(rm, convert(VecE2, car.pos))

function calc_subframe_interpolation_bounds(subframeind::Int, subframes_per_frame::Int)
    frameind_lo = int((subframeind-1 - mod(subframeind-1, subframes_per_frame))/subframes_per_frame)+1
    frameind_hi = frameind_lo + 1
    (frameind_lo, frameind_hi) # frameind low and high in stream
end
function calc_subframe_interpolation_scalar(subframeind::Int, subframes_per_frame::Int)
    # calc interpolation constant t for subframe (t ∈ [0,1])
    mod(subframeind-1,subframes_per_frame) / subframes_per_frame
end

function render_scene!( rm::RenderModel, s::Vector{Vehicle})

    if !isempty(s)
        render_car!(rm, s[1], COLOR_CAR_EGO)
    end
    for i = 2 : length(s)
        render_car!(rm, s[i], COLOR_CAR_OTHER)
    end
    rm
end

function render_lane_curve!(
    rm::RenderModel,
    lane::StreetLane;
    color :: Colorant = RGB(0xDD, 0x44, 0x44),
    line_width :: Real = 0.1
    )

    n = length(lane.curve.x)
    pts = Array(Float64, 2, n)
    pts[1,:] = lane.curve.x
    pts[2,:] = lane.curve.y
    add_instruction!(rm, render_line, (pts, color, line_width))
end
function render_streetnet_nodes!(
    rm::RenderModel,
    sn::StreetNetwork,
    color_nodes :: Colorant = Color(0xBB, 0xBB, 0xFF),
    size_nodes  :: Real = 0.25, # [m]
    )

    npts = num_vertices(sn.graph)

    pts = Array(Float64, 2, npts)

    for (i,node) in enumerate(vertices(sn.graph))
        pts[1,i] = node.pos.x
        pts[2,i] = node.pos.y
    end

    add_instruction!(rm, render_point_trail, (pts, color_nodes, size_nodes))

    rm
end
function render_streetnet_edges!(
    rm::RenderModel,
    sn::StreetNetwork;
    color :: Colorant = RGB(0x88, 0x88, 0xFF),
    line_width :: Real = 0.1
    )

    for e in edges(sn.graph)
    
        pts = [e.source.pos.x e.target.pos.x;
               e.source.pos.y e.target.pos.y]

        Renderer.add_instruction(rm, render_line, (pts, color, line_width))
    end
    
    rm
end
function render_streetnet_curves!(
    rm::RenderModel,
    sn::StreetNetwork;
    color :: Colorant = RGB(0xCC, 0x44, 0x44),
    line_width :: Real = 0.1
    )

    for tile in values(sn.tile_dict)
        for seg in values(tile.segments)
            for lane in values(seg.lanes)
                render_lane_curve!(rm, lane, color=color, line_width=line_width)
            end
        end
    end
    
    rm
end
function render_streetnet_roads!(
    rm::RenderModel,
    sn::StreetNetwork;
    color_asphalt       :: Colorant=COLOR_ASPHALT, 
    color_lane_markings :: Colorant=COLOR_LANE_MARKINGS,
    lane_marking_width  :: Real=0.15, # [m]
    lane_dash_len       :: Real=0.91, # [m]
    lane_dash_spacing   :: Real=2.74, # [m]
    lane_dash_offset    :: Real=0.00  # [m]
    )

    # tf_1 = [lane_dash_len,     lane_dash_width]
    # tf_2 = [lane_dash_spacing, 0.0]
    # tf_3 = [lane_dash_offset,  0.0]
    # user_to_device_distance!(ctx, tf_1)
    # user_to_device_distance!(ctx, tf_2)
    # user_to_device_distance!(ctx, tf_3)
    # lane_dash_len,lane_dash_width = (tf_1[1],-tf_1[2])
    # lane_dash_spacing = tf_2[1]
    # lane_dash_offset = tf_3[1]

    # render the asphalt
    for tile in values(sn.tile_dict)
        for seg in values(tile.segments)
            for lane in values(seg.lanes)
                n = length(lane.curve.x)
                pts = vcat(lane.curve.x', lane.curve.y')
                @assert(size(pts,1) == 2)
                add_instruction!(rm, render_line, (pts, color_asphalt, lane.width))
            end
        end
    end

    # render the lane edges

    rotL = [0.0 -1.0;  1.0 0.0]
    rotR = [0.0  1.0; -1.0 0.0]

    for tile in values(sn.tile_dict)
        for seg in values(tile.segments)
            for lane in values(seg.lanes)
                n = length(lane.curve.x)
                pts_left = Array(Float64, 2, length(lane.nodes))
                pts_right = Array(Float64, 2, length(lane.nodes))
                for (i,node) in enumerate(lane.nodes)
                    θ = Curves.curve_at(lane.curve, node.extind).θ
                    v = [cos(θ), sin(θ)]
                    p = [node.pos.x, node.pos.y]
                    pts_left[:,i]   = p + node.marker_dist_left * rotL * v
                    pts_right[:,i]  = p + node.marker_dist_right * rotR * v
                end

                add_instruction!(rm, render_line, (pts_left, color_lane_markings, lane_marking_width))
                add_instruction!(rm, render_line, (pts_right, color_lane_markings, lane_marking_width))
            end
        end
    end
    
    rm
end

function render_car!(
    rm::RenderModel,
    pdset::PrimaryDataset,
    carind::Int,
    frameind::Int;
    color :: Colorant = RGB(rand(), rand(), rand())
    )

    posGx = posGy = posGθ = 0.0

    if carind == CARIND_EGO
        posGx = gete(pdset, :posGx, frameind)
        posGy = gete(pdset, :posGy, frameind)
        posGθ = gete(pdset, :posGyaw, frameind)
    else
        validfind = frameind2validfind(pdset, frameind)
        posGx = getc(pdset, :posGx, carind, validfind)
        posGy = getc(pdset, :posGy, carind, validfind)
        posGθ = getc(pdset, :posGyaw, carind, validfind)
    end

    add_instruction!(rm, render_car, (posGx, posGy, posGθ, color))
    rm
end
function render_car!(
    rm::RenderModel,
    trajdata::DataFrame,
    carind::Int,
    frameind::Int;
    color :: Colorant = RGB(rand(), rand(), rand())
    )

    posGx = trajdata[frameind, :posGx]
    posGy = trajdata[frameind, :posGy]
    posGθ = trajdata[frameind, :yawG]

    if carind != CARIND_EGO
        posEx = getc(trajdata, :posEx, carind, frameind)
        posEy = getc(trajdata, :posEy, carind, frameind)
        velEx = getc(trajdata, :velEx, carind, frameind)
        velEy = getc(trajdata, :velEy, carind, frameind)

        posGx, posGy = Trajdata.ego2global(posGx, posGy, posGθ, posEx, posEy)



        velGx, velGy = Trajdata.ego2global(0.0, 0.0, posGθ, velEx, velEy)

        if hypot(velGx, velGy) > 3.0
            posGθ        = atan2(velGy, velGx)
        end
    end

    add_instruction!( render_car, (posGx, posGy, posGθ, color))
    rm
end
function render_scene!(
    rm::RenderModel,
    pdset::PrimaryDataset,
    frameind::Int;
    active_carid::Integer=CARID_EGO,
    color_active :: Colorant = COLOR_CAR_EGO,
    color_oth :: Colorant = COLOR_CAR_OTHER
    )

    @assert(frameind_inbounds(pdset, frameind))

    # render other cars first
    validfind = frameind2validfind(pdset, frameind)
    for carind in IterAllCarindsInFrame(pdset, validfind)
        carid = carind2id(pdset, carind, validfind)
        color = carid == active_carid ? color_active : color_oth

        render_car!(rm, pdset, carind, frameind, color=color)
    end

    rm
end
function render_scene!(
    rm::RenderModel,
    trajdata::DataFrame,
    frameind::Int;
    color_ego :: Colorant = COLOR_CAR_EGO,
    color_oth :: Colorant = COLOR_CAR_OTHER
    )

    @assert(0 < frameind ≤ size(trajdata, 1))

    # render other cars first
    for i = 1 : ncars_in_frame(trajdata, frameind)
        carind = i - 1
        render_car!(rm, trajdata, carind, frameind, color=color_oth)
    end

    # render ego car
    render_car!(rm, trajdata, CARIND_EGO, frameind, color=color_ego)

    rm
end

function camera_center_on_ego!(
    rm::RenderModel,
    pdset::PrimaryDataset,
    frameind::Int,
    zoom::Real = rm.camera_zoom # [pix/m]
    )
        
    @assert(frameind_inbounds(pdset, frameind))

    posGx = gete(pdset, :posGx, frameind)
    posGy = gete(pdset, :posGy, frameind)

    camera_set!(rm, posGx, posGy, zoom)
    rm
end
function camera_center_on_ego!(
    rm::RenderModel,
    trajdata::DataFrame,
    frameind::Int,
    zoom::Real = rm.camera_zoom # [pix/m]
    )

    posGx = trajdata[frameind, :posGx]
    posGy = trajdata[frameind, :posGy]

    camera_set!(rm, posGx, posGy, zoom)
    rm
end
function camera_center_on_carid!(
    rm::RenderModel,
    pdset::PrimaryDataset,
    carid::Integer,
    frameind::Integer,
    zoom::Real = rm.camera_zoom # [pix/m]
    )
        
    @assert(frameind_inbounds(pdset, frameind))

    validfind = frameind2validfind(pdset, frameind)
    carind = carid2ind(pdset, carid, validfind)
    posGx = get(pdset, :posGx, carind, validfind)
    posGy = get(pdset, :posGy, carind, validfind)

    camera_set!(rm, posGx, posGy, zoom)
    rm
end

# function reel_it(
#     runlog :: Matrix{Float64},
#     canvas_width :: Int,
#     canvas_height :: Int,
#     rm::RenderModel = RenderModel();
#     timescale::Int = 4
#     )

#     frameind = 1

#     function reel_render(t, dt, runlog::Matrix{Float64}, rm::RenderModel, canvas_width::Int, canvas_height::Int)
#         # t is the time into the sequence
#         # dt is the time to advance for the next frame
        
#         subframeind = int(t*10)+1

#         s = CairoRGBSurface(canvas_width, canvas_height)
#         ctx = creategc(s)

#         clear_setup!(rm)
#         set_background_color!(rm, colorscheme["background"])
#         render_road!(rm, road, -50.0, 5000.0)
#         render_scene_subframe!(rm, runlog, subframeind, 4)

#         # camera_set!(rn, runlog[frameind, LOG_COL_X], runlog[frameind, LOG_COL_Y], 12.0)
#         render(rm, ctx, canvas_width, canvas_height)

#         s
#     end

#     f = (t,dt) -> reel_render(t, dt, runlog, rm, canvas_width, canvas_height)
#     film = roll(f, fps=10, duration=(timescale*calc_nframes(runlog)/10)-1.0)
#     # write("output.gif", film)
#     return film
# end

function plot_traces(
    pdset::PrimaryDataset,
    sn::StreetNetwork,
    validfind::Integer,
    horizon::Integer,
    history::Integer;
    active_carid::Integer=CARID_EGO,
    canvas_width::Integer=1100, # [pix]
    canvas_height::Integer=500, # [pix]
    rendermodel::RenderModel=RenderModel(),
    camerazoom::Real=6.5,
    camerax::Real=get(pdset, :posGx, CARIND_EGO, validfind),
    cameray::Real=get(pdset, :posGy, CARIND_EGO, validfind),
    color_history::Colorant=RGBA(0.7,0.3,0.0,0.8),
    color_horizon::Colorant=RGBA(0.3,0.3,0.7,0.8),
    )


    s = CairoRGBSurface(canvas_width, canvas_height)
    ctx = creategc(s)
    clear_setup!(rendermodel)

    render_streetnet_roads!(rendermodel, sn)

    for carind in -1 : get_maxcarind(pdset, validfind)
        carid = carind2id(pdset, carind, validfind)
        render_trace!(rendermodel, pdset, carid, validfind - history, validfind, color=color_history)
        render_trace!(rendermodel, pdset, carid, validfind, validfind + horizon, color=color_horizon)
    end

    # render car positions
    render_scene!(rendermodel, pdset, validfind, active_carid=active_carid)

    camera_setzoom!(rendermodel, camerazoom)
    camera_set_pos!(rendermodel, camerax, cameray)
    render(rendermodel, ctx, canvas_width, canvas_height)
    s
end

function plot_manipulable_generated_future_traces(
    behavior::AbstractVehicleBehavior,
    pdset::PrimaryDataset,
    sn::StreetNetwork,
    active_carid::Integer,
    validfind_start::Integer,
    history::Integer,
    horizon::Integer;

    nsimulations::Integer=100,
    canvas_width::Integer=1100, # [pix]
    canvas_height::Integer=150, # [pix]
    rendermodel::RenderModel=RenderModel(),
    camerax::Real=get(pdset, :posGx, CARIND_EGO, validfind_start),
    cameray::Real=get(pdset, :posGy, CARIND_EGO, validfind_start),
    camerazoom::Real=6.5,
    color_history::Colorant=RGB(0.7,0.3,0.0,0.8),
    color_horizon::Colorant=RGB(0.3,0.3,0.7,0.8),
    color_dot::Colorant=RGB(0.7,0.3,0.3,0.5),
    color_stroke::Colorant=RGB(0.0,0.0,0.0,0.0),
    dot_radius::Real=0.25, # [m]
    )

    pdset_sim = deepcopy(pdset)
    basics = FeatureExtractBasicsPdSet(pdset, sn)
    validfind_end = validfind_start+horizon
    positions = Array(Float64, nsimulations, horizon, 2) # {posGx, posGy}
    for i = 1 : nsimulations
        simulate!(basics, behavior, active_carid, validfind_start, validfind_end)
        
        for (j,validfind_final) in enumerate(validfind_start+1 : validfind_start+horizon)

            carind = carid2ind(pdset_sim, active_carid, validfind_final)
            positions[i,j,1] = get(pdset_sim, :posGx, carind, validfind_final)
            positions[i,j,2] = get(pdset_sim, :posGy, carind, validfind_final)
        end
    end

    validfind = validfind_start
    @manipulate for validfind = validfind_start-history : validfind_end

        s = CairoRGBSurface(canvas_width, canvas_height)
        ctx = creategc(s)
        clear_setup!(rendermodel)

        render_streetnet_roads!(rendermodel, sn)
        
        for carind in -1 : get_maxcarind(pdset, validfind)
            carid = carind2id(pdset, carind, validfind)
            if carid != active_carid || validfind ≤ validfind_start
                frameind = validfind2frameind(pdset, validfind)
                render_car!(rendermodel, pdset, carind, frameind, color=(carid==active_carid?COLOR_CAR_EGO:COLOR_CAR_OTHER))
            end
        end

        if validfind > validfind_start
            j = validfind - validfind_start
            for i = 1 : nsimulations
                x, y = positions[i,j,1], positions[i,j,2]
                add_instruction!(rendermodel, render_circle, (x,y,dot_radius,color_dot,color_stroke))
            end
        end


        camera_setzoom!(rendermodel, camerazoom)
        camera_set_pos!(rendermodel, camerax, cameray)
        render!(ctx, canvas_width, canvas_height, rendermodel)
        s
    end
end
function plot_manipulable_pdset(
    pdset::PrimaryDataset,
    sn::StreetNetwork;
    canvas_width::Integer=1100, # [pix]
    canvas_height::Integer=500, # [pix]
    rendermodel::RenderModel=RenderModel(),
    camerazoom::Real=6.5,
    active_carid::Integer=CARID_EGO
    )

    nvalidfinds_total = nvalidfinds(pdset)
    validfind = 1
    @manipulate for validfind = 1 : nvalidfinds_total

        s = CairoRGBSurface(canvas_width, canvas_height)
        ctx = creategc(s)
        clear_setup!(rendermodel)

        frameind = validfind2frameind(pdset, validfind)
        render_streetnet_roads!(rendermodel, sn)
        render_scene!(rendermodel, pdset, frameind, active_carid=active_carid)
        camera_center_on_carid!(rendermodel, pdset, active_carid, frameind, camerazoom)
        
        render(rendermodel, ctx, canvas_width, canvas_height)
        s
    end
end

function reel_pdset(
    pdset::PrimaryDataset,
    sn::StreetNetwork;
    canvas_width::Integer=1100, # [pix]
    canvas_height::Integer=500, # [pix]
    rendermodel::RenderModel=RenderModel(),
    camerazoom::Real=6.5,
    active_carid::Integer=CARID_EGO
    )

    function reel_render(
        t::Float64, # the time into the sequence
        dt::Float64, # dt is the time to advance for the next frame
        pdset::PrimaryDataset,
        sn::StreetNetwork,
        rm::RenderModel,
        canvas_width::Int,
        canvas_height::Int,
        camerazoom::Real,
        active_carid::Integer
        )

        validfind = clamp(int(20*t)+1, 1, nvalidfinds(pdset))

        s = CairoRGBSurface(canvas_width, canvas_height)
        ctx = creategc(s)
        clear_setup!(rendermodel)

        frameind = validfind2frameind(pdset, validfind)
        render_streetnet_roads!(rendermodel, sn)
        render_scene!(rendermodel, pdset, frameind)
        camera_center_on_carid!(rendermodel, pdset, active_carid, frameind, camerazoom)
        
        render(rendermodel, ctx, canvas_width, canvas_height)
        s
    end

    f = (t,dt) -> reel_render(t, dt, pdset, sn, rendermodel, canvas_width, canvas_height,
                              camerazoom, active_carid)
    film = roll(f, fps=20, duration=(nvalidfinds(pdset)/20-1))
    # write("output.gif", film)
    return film
end

function generate_and_plot_manipulable_gridcount_set(
    behavior::AbstractVehicleBehavior,
    pdset::PrimaryDataset,
    sn::StreetNetwork,
    active_carid::Integer,
    validfind_start::Integer,
    history::Integer,
    horizon::Integer;
    disc_bounds_s::(Float64, Float64)=(0.0,150.0),
    disc_bounds_t::(Float64, Float64)=(-10.0, 10.0),
    nbinsx::Integer=101,
    nbinsy::Integer=51,
    nsimulations::Integer=1000,
    canvas_width::Integer=1100, # [pix]
    canvas_height::Integer=150, # [pix]
    rendermodel::RenderModel=RenderModel(),
    camerazoom::Real=6.5,
    color_prob_lo::Colorant=RGBA(0.0,0.0,0.0,0.0),
    color_prob_hi::Colorant=RGBA(1.0,0.0,0.0,1.0),
    color_history::Colorant=RGBA(0.7,0.3,0.0,0.8),
    color_horizon::Colorant=RGBA(0.3,0.3,0.7,0.8),
    count_adjust_exponent::Float64=0.25,
    )

    histobin_params = ParamsHistobin(LinearDiscretizer(linspace(disc_bounds_s..., nbinsx+1)),
                                     LinearDiscretizer(linspace(disc_bounds_t..., nbinsy+1)))

    # ncars = get_num_cars_in_frame(pdset, validfind_start)

    pdset_sim = deepcopy(pdset)

    gridcounts = Array(Matrix{Float64}, horizon) # only frames past start, noninclusive
    for i = 1 : length(gridcounts)
        gridcounts[i] = Array(Float64, nbinsx, nbinsy)
    end

    calc_future_grid_counts!(gridcounts, histobin_params, pdset_sim, sn, behavior,
                             active_carid, validfind_start, validfind_start + horizon, nsimulations)

    for gridcount in gridcounts
        maxcount = maximum(gridcount)
        for i = 1 : length(gridcount)
            gridcount[i] = (gridcount[i]/maxcount)^count_adjust_exponent  #NOTE(tim): to make low probs stand out more
        end
    end

    # -----------

    carind_start = carid2ind(pdset, active_carid, validfind_start)
    posGx_start = get(pdset, :posGx, carind_start, validfind_start)
    posGy_start = get(pdset, :posGy, carind_start, validfind_start)

    validfind = validfind_start
    validfind_end = validfind_start+horizon
    @manipulate for validfind = validfind_start-history : validfind_end

        s = CairoRGBSurface(canvas_width, canvas_height)
        ctx = creategc(s)
        clear_setup!(rendermodel)

        render_streetnet_roads!(rendermodel, sn)

        for carind in -1 : get_maxcarind(pdset, validfind)
            carid = carind2id(pdset, carind, validfind)
            # render_trace!(rendermodel, pdset, carid, validfind_start - history, validfind_start, color=color_history)
            if carid != active_carid
                # render_trace!(rendermodel, pdset, carid, validfind_start, validfind_end, color=color_horizon)
            else
                if validfind > validfind_start
                    gridcount = gridcounts[validfind - validfind_start]

                    add_instruction!(rendermodel, render_colormesh, (gridcount, 
                                      histobin_params.discx.binedges .+ posGx_start,
                                      histobin_params.discy.binedges .+ posGy_start,
                                      color_prob_lo, color_prob_hi))
                end
            end
        end
        
        for carind in -1 : get_maxcarind(pdset, validfind)
            carid = carind2id(pdset, carind, validfind)
            if carid != active_carid || validfind ≤ validfind_start
                frameind = validfind2frameind(pdset, validfind)
                render_car!(rendermodel, pdset, carind, frameind, color=(carid==active_carid?COLOR_CAR_EGO:COLOR_CAR_OTHER))
            end
        end

        active_carind = carid2ind(pdset, active_carid, validfind)
        camerax = get(pdset, :posGx, active_carind, validfind)
        cameray = get(pdset, :posGy, active_carind, validfind)

        camera_setzoom!(rendermodel, camerazoom)
        camera_set_pos!(rendermodel, camerax, cameray)
        render(rendermodel, ctx, canvas_width, canvas_height)
        s
    end
end