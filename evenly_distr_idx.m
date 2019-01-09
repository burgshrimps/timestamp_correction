function result_idx = evenly_distr_idx(len, num_miss_frames)
    % gets length of an interval and number of missed frames and returns
    % evenly distributed index positions 
    % @param len : length of interval
    % @param num_miss_frames : number of frames to be missed
    % @return result_idx : evenly distrubuted index positions over the
    % intervall
    result_idx = zeros(1,num_miss_frames);
    tmp = len/(num_miss_frames+1);
    for i = 1:num_miss_frames
        result_idx(i) = round(i * tmp);
    end
end