
class window.ExperimentMonitor

  constructor: (@experiment_id) ->
    @update_interval = 20
    @obj_id = "experiment_monitor_#{@experiment_id}"

    window.scalarm_objects[@obj_id] = this
    @schedule_update()

  update: ->
    monitor = this
    $.ajax({
      url: "/experiments/#{monitor.experiment_id}/experiment_stats",
      success: (statistics) ->
        monitor.update_statistics(JSON.parse(statistics))
    })
    $.ajax({
      url: "/experiments/#{monitor.experiment_id}/experiment_moes",
      success: (response) ->
        monitor.update_moes(JSON.parse(response))
    })

  update_statistics: (statistics) ->
    $("#exp_all_counter").html(statistics.all.toString().with_delimeters())
    $("#exp_generated_counter").html(statistics.generated.toString().with_delimeters())
    $("#exp_sent_counter").html(statistics.sent.toString().with_delimeters())
    $("#exp_done_counter").html(statistics.done_num.toString().with_delimeters())
    $("#exp_done_percentage_counter").html(statistics.done_percentage)

    bar_colors = eval(statistics.progress_bar)
    canvas = document.getElementById("exp_progress_bar_2")
    context = canvas.getContext("2d")
    part_width = canvas.width / bar_colors.length

    context.fillStyle = "rgb(255, 255, 255)";
    context.fillRect(0, 10, canvas.width, canvas.height - 10);

    for i in [0..bar_colors.length]
      context.fillStyle = if(bar_colors[i] == 0) then "#BDBDBD" else "rgb(0, #{bar_colors[i]}, 0)"
      context.fillRect(part_width * i, 10, part_width*0.95, canvas.height - 10)

    if(statistics.avg_simulation_time != undefined)
      $("#ei_perform_time_avg").html(statistics.avg_simulation_time)
      $("#p_ei_perform_time_avg").show()
    if(statistics.predicted_finish_time != undefined)
      $("#predicted_finish_time").html(statistics.predicted_finish_time)
      $("#p_predicted_finish_time").show()
#      if #instances_done == #experiment_size
    if(statistics.done_num == statistics.all)
      $("#p_predicted_finish_time").hide()
      $("#get_results_button").show()

  generate_html: (parent_id) ->
    elements = [
      "ALL: ", $('<span>').attr('id', 'exp_all_counter').text("0"),
      " - GENERATED: ", $('<span>').attr('id', 'exp_generated_counter').text("0"),
      " - DONE: ", $('<span>').attr('id', 'exp_done_counter').text("0"),
      " ( ", $('<span>').attr('id', 'exp_done_percentage_counter').text("0"), " % COMPLETED )",
      " - SENT: ", $('<span>').attr('id', 'exp_sent_counter').text("0"),
    ]

    stats_par = $('<p>')

    for element in elements
      stats_par.append(element)

    $("##{parent_id}").append(stats_par)
      .append($('<p>').attr('id', 'p_ei_perform_time_avg').append("Average time of performing a single experiment instance: ")
        .append($('<span>').attr('id', 'ei_perform_time_avg')).hide())
      .append($('<p>').attr('id', 'p_predicted_finish_time').append("Predicted time of finishing the experiment: ")
        .append($('<span>').attr('id', 'predicted_finish_time')).hide())

    $("#experiment_progress_bar").append($('<canvas>').attr('id', 'exp_progress_bar_2'))

    monitor = this
    $.ajax({
      url: "/experiments/#{monitor.experiment_id}/experiment_stats",
      success: (statistics) ->
        monitor.update_statistics(JSON.parse(statistics))
    })

  schedule_update: ->
    setTimeout("window.scalarm_objects['#{"experiment_monitor_#{@experiment_id}"}'].update()", 1000)
    setInterval("window.scalarm_objects['#{"experiment_monitor_#{@experiment_id}"}'].update()", @update_interval*1000)
    
  update_moes: (moes_info) ->
    $(".moe_list").each((i, select_element) ->
      selected_option = $(select_element).find(":selected").val()
      $(select_element).html(moes_info.moes)
      
      $(select_element).find("option").filter(() ->
        return $(this).val() == selected_option    
      ).attr('selected', true)  
    )
    
    $(".moes_and_params_list").each((i, select_element) ->
      selected_option = $(select_element).find(":selected").val()
      $(select_element).html(moes_info.moes_and_params)
      
      $(select_element).find("option").filter(() ->
        return $(this).val() == selected_option    
      ).attr('selected', true)  
    )
    