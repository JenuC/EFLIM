% Calculate the average of non-zero elements

%%ELiiiiiii, 20240119
%%ELiiiiiii, 20240226, use mean ('omitnan') instead of sum() ./ sum(~=0)
function output = mean_nz(input, axis)
%%
if nargin < 2
    axis = 'all';
end

%%
input(input==0) = nan;
output = mean(input, axis, 'omitnan');
output(isnan(output)) = 0;
