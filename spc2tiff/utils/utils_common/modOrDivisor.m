% 'modOrDivisor' acts the same with 'mod' except:
%   mod(2x, x) = 0
%   modOrDivisor(2x, x) = x

% ELiiiiiii, 20240313
function output = modOrDivisor(x, y)
    output = mod(x,y);
    if output == 0
        output = y;
    end