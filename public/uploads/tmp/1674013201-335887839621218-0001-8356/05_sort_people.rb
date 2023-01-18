# @param {String[]} names
# @param {Integer[]} heights
# @return {String[]}
def sort_people(names, heights)
    dict = {}
    heights.each_with_index do |height, index| 
        dict[height] = names[index]
    end

    sorted_names = dict.sort_by { |key, value| key  }.reverse.map { |key, value| value }
    sorted_names
    
end
