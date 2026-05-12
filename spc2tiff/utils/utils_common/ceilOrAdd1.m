% 'ceilOrAdd1' acts the same with 'ceil' except:
%   ceil(7) = 7
%   ceilOrAdd1(7) = 8

% ELiiiiiii, 20240313
function outputNum = ceilOrAdd1(num)
    if mod(num,1) == 0
        outputNum = num + 1;
    else
        outputNum = ceil(num);
    end