classdef SolverCallCounter < handle
    %SOLVERCALLCOUNTER Delegate to solve_storenet while counting invocations.
    %   Used by runner tests to prove that resumed runs reuse checkpointed
    %   rows instead of re-solving them.

    properties
        Calls (1, 1) double = 0
    end

    methods
        function [solution, metrics] = solve(obj, data, config, strategy)
            obj.Calls = obj.Calls + 1;
            [solution, metrics] = solve_storenet(data, config, strategy);
        end
    end
end
