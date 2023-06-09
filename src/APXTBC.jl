
using DataStructures
using StatsBase
using Base.Threads

include("graphs/temporal_graph.jl")
# Shortest
include("centralities/shortest_temporal/temporal_shortest_betweenness.jl")
include("centralities/shortest_temporal/onbra.jl")
include("centralities/shortest_temporal/rtb.jl")
include("centralities/shortest_temporal/trk.jl")

# Shortest Foremost
include("centralities/shortest_foremost/temporal_shortest_foremost_betweenness.jl")
include("centralities/shortest_foremost/onbra_shortest_foremost.jl")
include("centralities/shortest_foremost/rtb_shortest_foremost.jl")
include("centralities/shortest_foremost/trk_shortest_foremost.jl")

# Prefix Foremost
include("centralities/prefix_foremost/prefix_foremost_betweenness.jl")
include("centralities/prefix_foremost/onbra_prefix_foremost.jl")
include("centralities/prefix_foremost/rtb_prefix_foremost.jl")
include("centralities/prefix_foremost/trk_prefix_foremost.jl")
# Distance function
include("temporal_neighborhood_function/mt_diameter.jl")
include("centralities/utilities.jl")
include("statistics/rankings.jl")
include("statistics/correlations_and_error.jl")

#PARALLEL 
# EXACT
include("parallel/shortest_temporal/mt_temporal_shortest_betweenness.jl")
include("parallel/shortest_foremost/mt_temporal_shortest_foremost_betweenness.jl")
include("parallel/prefix_foremost/mt_prefix_foremost_betweenness.jl")
# APX RANDOM TEMPORAL BETWEENNESS
include("parallel/shortest_temporal/mt_rtb.jl")
include("parallel/shortest_foremost/mt_rtb_shortest_foremost.jl")
include("parallel/prefix_foremost/mt_rtb_prefix_foremost.jl")
# APX ONBRA
include("parallel/shortest_temporal/mt_onbra.jl")
include("parallel/shortest_foremost/mt_onbra_shortest_foremost.jl")
include("parallel/prefix_foremost/mt_onbra_prefix_foremost.jl")
# APX SRTP
include("parallel/shortest_temporal/mt_trk.jl")
include("parallel/shortest_foremost/mt_trk_shortest_foremost.jl")
include("parallel/prefix_foremost/mt_trk_prefix_foremost.jl")


