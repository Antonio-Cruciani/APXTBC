

function threaded_progressive_trk_topk(tg::temporal_graph,eps::Float64,delta::Float64,k::Int64,verbose_step::Int64,bigint::Bool,diam::Int64 = -1,start_factor::Int64 = 100,sample_step::Int64 = 10,hb::Bool = false)

    start_time = time()
    tal::Array{Array{Tuple{Int64,Int64}}} = temporal_adjacency_list(tg)
    tn_index::Dict{Tuple{Int64,Int64},Int64} = temporal_node_index_srtp(tg)
    balancing_factor::Float64 = 0.001

    local_temporal_betweenness::Vector{Vector{Float64}} = [zeros(tg.num_nodes) for i in 1:nthreads()]
    approx_top_k::Array{Tuple{Int64,Float64}} =  Array{Tuple{Int64,Float64}}([])
    omega::Int64 = 1000
    t_diam::Float64 = 0.0
    union_sample::Int64 = min(tg.num_nodes,max(sqrt(lastindex(tg.temporal_edges))/nthreads(),k+20))
    if (diam == -1) && (!hb)
        println("Approximating diameter ")
        diam,_,_,_,_,t_diam = threaded_temporal_shortest_diameter(tg,64,verbose_step)
        println("Task completed in "*string(round(t_diam;digits = 4))*". Δ = "*string(diam))
        diam+=1
    end
    if !hb
        omega = trunc(Int,(0.5/eps^2) * ((floor(log2(diam-2)))+log(1/delta)))
    else
        omega = trunc(Int,(1.0/(2*eps^2))*log2(2*tg.num_nodes/delta))
    end
    println("Top-k algorithm: k =  "*string(k)*"  union sample = "*string(union_sample))
    println("Maximum sample size "*string(omega))
    tau::Int64 = trunc(Int64,omega/start_factor)
    s::Int64 = 0
    z::Int64 = 0
    println("Bootstrap phase "*string(tau)*" iterations")
    Base.Threads.@threads for i in 1:tau
        sample::Array{Tuple{Int64,Int64}} = onbra_sample(tg, 1)
        s = sample[1][1]
        z = sample[1][2]
        _trk_sh_accumulate!(tg,tal,tn_index,bigint,s,z,local_temporal_betweenness[Base.Threads.threadid()])
    end
    betweenness = reduce(+, local_temporal_betweenness)
    betweenness = betweenness .* [1/tau]
    for u in 1:tg.num_nodes
        push!(approx_top_k,(u,betweenness[u]))
    end
    sort!(approx_top_k, by=approx_top_k->-approx_top_k[2])
    eps_lb::Array{Float64} = zeros(tg.num_nodes)
    eps_ub::Array{Float64} = zeros(tg.num_nodes)
    delta_lb_min_guess::Array{Float64} = [0.0]
    delta_ub_min_guess::Array{Float64} = [0.0]
    delta_lb_guess::Array{Float64} = zeros(tg.num_nodes)
    delta_ub_guess::Array{Float64} = zeros(tg.num_nodes)
    _compute_δ_guess_topk!(betweenness,eps,delta,balancing_factor,eps_lb,eps_ub,delta_lb_min_guess,delta_ub_min_guess,delta_lb_guess,delta_ub_guess,k,approx_top_k,start_factor,union_sample) 
    println("Bootstrap completed ")
    local_temporal_betweenness = [zeros(tg.num_nodes) for i in 1:nthreads()]
    betweenness = zeros(tg.num_nodes)
    sampled_so_far::Int64 = 0
    stop::Array{Bool} = [false]
    while sampled_so_far <= omega && !stop[1]
        approx_top_k = Array{Tuple{Int64,Float64}}([])
        Base.Threads.@threads for i in 1:sample_step
            sample::Array{Tuple{Int64,Int64}} = onbra_sample(tg, 1)
            s = sample[1][1]
            z = sample[1][2]
            _trk_sh_accumulate!(tg,tal,tn_index,bigint,s,z,local_temporal_betweenness[Base.Threads.threadid()])
        end
        sampled_so_far += sample_step
        betweenness = reduce(+, local_temporal_betweenness)
        for u in 1:tg.num_nodes
            push!(approx_top_k,(u,betweenness[u]))
        end
        sort!(approx_top_k, by=approx_top_k->-approx_top_k[2])
        _compute_finished_topk!(stop,omega,approx_top_k[begin:union_sample],sampled_so_far,eps,eps_lb,eps_ub,delta_lb_guess,delta_ub_guess,delta_lb_min_guess[1],delta_ub_min_guess[1],union_sample)   
        if (verbose_step > 0 && sampled_so_far % verbose_step == 0)
            finish_partial = string(round(time() - start_time; digits=4))
            println("P-TRK-SH (TOP-K). Processed " * string(sampled_so_far) * " pairs in " * finish_partial * " seconds ")
        end
    end
    if stop[1]
        println("Progressive sampler converged at "*string(sampled_so_far)*"/"*string(omega)*" iterations")
    end
    return approx_top_k,eps_lb,eps_ub,sampled_so_far,omega,time()-start_time


end





function compute_bet_err_topk(eps::Float64,eps_lb::Array{Float64},eps_ub::Array{Float64},start_factor::Int64,k::Int64,approx_top_k::Array{Tuple{Int64,Float64}},union_sample::Int64)::Tuple{Array{Float64},Array{Float64}}
    n::Int64 = lastindex(eps_lb)
    bet::Array{Float64} = zeros(n)
    max_error::Float64 = sqrt(start_factor) * eps/4
    Base.Threads.@threads for i in 1:union_sample 
        bet[i] = approx_top_k[i][2]
    end
    eps_ub[1] = max(eps,(bet[1]-bet[2])/2)
    eps_lb[1] = 10
    Base.Threads.@threads for i in 2:k
        eps_lb[i] = max(eps,(bet[i-1]-bet[i])/2)
        eps_ub[i] = max(eps,(bet[i]-bet[i+1])/2)
    end
    Base.Threads.@threads for i in (k+1):union_sample
        eps_lb[i] = 10
        eps_ub[i] = max(eps,bet[k-1]+(bet[k-1]-bet[k])/2 - bet[i])
    end
    for i in 1:(k-1)
        if bet[i] - bet[i + 1] < max_error
            eps_lb[i] = eps
            eps_ub[i] = eps
            eps_lb[i+1] = eps
            eps_ub[i+1] = eps
        end
    end
    for i in (k+1):union_sample
        if bet[k] - bet[i] < max_error
            eps_lb[k] = eps
            eps_ub[k] = eps
            eps_lb[i] = eps
            eps_ub[i] = eps
        end
    end
    return eps_lb,eps_ub
end

function _compute_δ_guess_topk!(betweenness::Array{Float64},eps::Float64,delta::Float64,balancing_factor::Float64,eps_lb::Array{Float64},eps_ub::Array{Float64},delta_lb_min_guess::Array{Float64},delta_ub_min_guess::Array{Float64},delta_lb_guess::Array{Float64},delta_ub_guess::Array{Float64},k::Int64,approx_top_k::Array{Tuple{Int64,Float64}},start_factor::Int64,union_sample::Int64) 

    n::Int64 = lastindex(betweenness)
    v::Int64 = -1
    a::Float64 = 0
    b::Float64 = 1.0 / eps / eps* log(n* 4* (1-balancing_factor)/delta)
    c::Float64 = (a+b)/2
    summation::Float64 = 0.0
    eps_lb,eps_ub = compute_bet_err_topk(eps,eps_lb,eps_ub,start_factor,k,approx_top_k,union_sample)
  
    while (b-a > eps/10.0)
        c = (b+a)/2
        summation = 0
        for i in 1:n
            summation += exp(-c * eps_lb[i]*eps_lb[i] / betweenness[i] )
            summation += exp(-c * eps_ub[i]*eps_ub[i] / betweenness[i] )
        end
        summation += exp(-c * eps_lb[union_sample-1]*eps_lb[union_sample-1] / betweenness[union_sample-1] ) * (n-union_sample)
        summation += exp(-c * eps_ub[union_sample-1]*eps_ub[union_sample-1] / betweenness[union_sample-1] ) * (n-union_sample)
        if (summation >= delta/2.0 * (1-balancing_factor))
            a = c 
        else
            b = c
        end
    end
    delta_lb_min_guess[1] = exp(-b * eps_lb[union_sample-1]* eps_lb[union_sample-1] / betweenness[union_sample-1]) + delta*balancing_factor/4.0 / n
    delta_ub_min_guess[1] = exp(-b * eps_ub[union_sample-1]* eps_ub[union_sample-1] / betweenness[union_sample-1] ) + delta*balancing_factor/4.0 / n
    Base.Threads.@threads for v in 1:n
        delta_lb_guess[v] = delta_lb_min_guess[1]
        delta_ub_guess[v] =  delta_ub_min_guess[1] 
    end

    Base.Threads.@threads for i in 1:union_sample
        v = approx_top_k[i][1]
        delta_lb_guess[v] = exp(-b *  eps_lb[i]*eps_lb[i]/ betweenness[i])+ delta*balancing_factor/4.0 / n
        delta_ub_guess[v] = exp(-b *  eps_ub[i]*eps_ub[i] / betweenness[i]) + delta*balancing_factor/4.0 / n
    end 

    return nothing
end


function _compute_finished_topk!(stop::Array{Bool},omega::Int64,top_k_approx::Array{Tuple{Int64,Float64}},sampled_so_far::Int64,eps::Float64,eps_lb::Array{Float64},eps_ub::Array{Float64},delta_lb_guess::Array{Float64},delta_ub_guess::Array{Float64},delta_lb_min_guess::Float64,delta_ub_min_guess::Float64,union_sample::Int64)
    #j::Int64 = 1
    k = lastindex(top_k_approx)
    all_finished::Bool = true
    finished::Array{Bool} = falses(union_sample)
    betweenness::Array{Float64} = zeros(union_sample)
    Base.Threads.@threads for i in 1:(union_sample-1)
        betweenness[i] = top_k_approx[i][2] / sampled_so_far
        eps_lb[i] = commpute_f(betweenness[i],sampled_so_far,delta_lb_guess[top_k_approx[i][1]],omega)
        eps_ub[i] = compute_g(betweenness[i],sampled_so_far,delta_ub_guess[top_k_approx[i][1]],omega)
        #j+=1
    end
    betweenness[union_sample] = top_k_approx[union_sample][2] / sampled_so_far
    eps_lb[union_sample] = commpute_f(betweenness[union_sample],sampled_so_far,delta_lb_min_guess,omega)
    eps_ub[union_sample] = compute_g(betweenness[union_sample],sampled_so_far,delta_ub_min_guess,omega)
    for i in 1:union_sample
        if i == 1
            finished[i] = (betweenness[i] - eps_lb[i] > betweenness[i+1] + eps_ub[i+1] )
        elseif i < k
            finished[i] = (betweenness[i-1] - eps_lb[i-1] > betweenness[i] + eps_ub[i] ) & (betweenness[i] - eps_lb[i] > betweenness[i+1] + eps_ub[i+1] )
        else
            finished[i] = (betweenness[k-1] - eps_ub[k-1] > betweenness[i] + eps_ub[i] )
        end
        
        all_finished = all_finished & finished[i] ||( (eps_lb[i] < eps) & (eps_ub[i] < eps))
    end
    stop[1] = all_finished

    return nothing
end