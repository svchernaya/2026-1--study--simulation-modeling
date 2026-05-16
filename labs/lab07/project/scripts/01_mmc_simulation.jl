# # Модель M/M/c
#
# Выполнение задания 7.1.5

using DrWatson
@quickactivate "project"

using StableRNGs, Distributions, ConcurrentSim, ResumableFunctions
using DataFrames, CSV, Plots

rng = StableRNG(123)
num_customers = 100                    
num_servers = 2                        
mu = 1.0 / 2                           
lam = 0.9                              
arrival_dist = Exponential(1 / lam)    
service_dist = Exponential(1 / mu)     

records = [] 

@resumable function customer(env, server, id, t_a, d_s)
    @yield timeout(env, t_a)
    t_arr = now(env)
    
    @yield request(server)
    t_start = now(env)
    
    @yield timeout(env, rand(rng, d_s))
    t_end = now(env)
    
    @yield unlock(server)
    
    push!(records, (id=id, arrival=t_arr, start=t_start, finish=t_end,
                    wait_time=t_start - t_arr, service_time=t_end - t_start))
end

function run_simulation()
    sim = Simulation()
    server = Resource(sim, num_servers)
    arrival_time = 0.0
    
    for i = 1:num_customers
        arrival_time += rand(rng, arrival_dist)
        @process customer(sim, server, i, arrival_time, service_dist)
    end
    
    run(sim)
end

run_simulation()

df = DataFrame(records)
mkpath(datadir("mmc"))
CSV.write(datadir("mmc", "results.csv"), df)

p1 = histogram(df.wait_time, bins=30, 
               xlabel="Время ожидания", ylabel="Частота",
               title="Распределение времени ожидания в очереди",
               legend=false)

p2 = histogram(df.service_time, bins=30,
               xlabel="Время обслуживания", ylabel="Частота",
               title="Распределение времени обслуживания",
               legend=false)

cumulative_avg = [mean(df.wait_time[1:i]) for i in 1:nrow(df)]
p3 = plot(1:nrow(df), cumulative_avg,
          xlabel="Номер клиента", ylabel="Среднее время ожидания",
          title="Сходимость среднего времени ожидания",
          legend=false, linewidth=2)

p_final = plot(p1, p2, p3, layout=(3,1), size=(600, 900))
mkpath(plotsdir())
savefig(plotsdir("mmc_analysis.png"))

println("Среднее время ожидания в очереди: ", round(mean(df.wait_time), digits=3))
println("Среднее время обслуживания: ", round(mean(df.service_time), digits=3))
println("Среднее время в системе: ", round(mean(df.service_time + df.wait_time), digits=3))
println("Количество обслуженных клиентов: ", nrow(df))
println("\nГрафик сохранён: plots/mmc_analysis.png")
println("Данные сохранены: data/mmc/results.csv")
