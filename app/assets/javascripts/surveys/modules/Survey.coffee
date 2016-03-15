require 'velocity-animate'
require 'parsleyjs'
require 'core-js/modules/es6.array.is-array'
rangeslider = require 'rangeslider.js'
throttle = require 'lodash.throttle'

scroll_duration = 500
scroll_easing = [0.19, 1, 0.22, 1]
Utils = require './SurveyUtils.coffee'

chosen_options =
  disable_search_threshold: 10
  width: '75%'

Survey =
  current_block: 0
  submitted: []
  survey_conditionals: {}

  init: ->
    @$window = $(window)
    scroll(0,0)
    @$survey_form = $('[data-survey-form]')
    @survey_blocks = $('[data-survey-block]')
    @$intro = $('[data-intro]')
    @$thank_you = $('[data-thank-you]')
    @setFormValidationSections()
    @survey_progress = $('[data-survey-progress]')
    @initConditionals()
    @listeners()
    @initBlocks()
    @initRangeSliders()

  listeners: ->
    $('[data-next-survey]').on 'click', @nextSurvey.bind(@)
    $('[data-next-survey-block]').on 'click', @validateCurrentQuestion.bind(@)
    $('[data-prev-survey-block]').on 'click', @prevBlock.bind(@)
    $('[data-show-title]').on 'change', @toggleShowQuestionGroupTitle.bind(@)
    $('[data-chosen-select]').chosen chosen_options
    @$window.scroll( throttle( @handleScroll.bind(@), 250) );

  handleScroll: ->
    return if @animating
    docHeight = @$window.innerHeight()
    distanceToTop = @$window.scrollTop()
    windowHeight = @$window.innerHeight()
    threshold =  (distanceToTop + windowHeight) - windowHeight * .5

    @survey_blocks.each (i, block) =>
      $block = $(block)
      return if $block.hasClass 'not-seen'
      blockOffset = $block.offset().top
      if blockOffset > distanceToTop && blockOffset < threshold
        $block.removeClass 'disabled'
      else
        $block.addClass 'disabled'

  initBlocks: ->
    @indexBlocks()
    window.scrollTo(0,0)
    $(@survey_blocks[@current_block]).removeClass 'disabled not-seen'

  indexBlocks: (cb = null) ->
    $('[data-survey-block].hidden').removeAttr 'data-survey-block'
    $survey_blocks = $('[data-survey-block]:not(.hidden)')
    $survey_blocks.each (i, block) ->
      $block = $(block)
      $block.attr 'data-survey-block', i

    cb() if cb

  nextSurvey: (e) ->
    e.preventDefault();
    if $(e.target).data('next-survey') # Last Survey
      @submitAllQuestionGroups()
      @showThankYou()
    else
      $(e.target).parents('.block').addClass 'hidden'
      @nextBlock()

  submitAllQuestionGroups: ->
    @$survey_form.each @submitQuestionGroup.bind(@)

  submitQuestionGroup: (index) ->
    return if @submitted.indexOf(index) isnt -1
    @submitted.push index
    $form = $("form[data-question-group='#{index}']")
    url = $form.attr 'action'
    method = $form.attr 'method'
    _context = @
    
    $form.on 'submit', (e) ->
      e.preventDefault()
      data = _context.processQuestionGroupData $(this).serializeArray()
      $.ajax
        url: url
        method: method
        data: JSON.stringify(data)
        dataType: 'json'
        contentType: 'application/json'
        success: (e) -> console.log 'success', e
        error: (e) -> console.log 'error', e

    $form.submit()

  processQuestionGroupData: (data) ->
    _postData = {}
    answer_group = {}
    data.map (field) ->
      name = field.name
      value = field.value
      if name.indexOf('answer_group') isnt -1
        fielddata = name.replace('answer_group', '').split '['
        answer_id = fielddata[1].replace ']', ''
        answer_key = fielddata[2].replace ']', ''
        if name.indexOf('[]') is -1 #Single Answer Question
          val = {}
          val[answer_key] = value
          answer_group[answer_id] = val
        else #Multi-Select (Checkbox)
          if value isnt "0"
            if answer_group[answer_id]?
              answer_group[answer_id][answer_key].push "0"
              answer_group[answer_id][answer_key].push value
            else
              answer_text = {}
              values = []
              values.push "0"
              values.push value
              answer_text[answer_key] = values
              answer_group[answer_id] = answer_text

      else
        _postData[name] = value

    _postData['answer_group'] = answer_group
    _postData

  validateBlock: (e, cb) ->
    toIndex = @current_block + 1
    $block = $(@survey_blocks[toIndex])
    @validateCurrentQuestion()

  updateCurrentBlock: ->
    return if @animating
    $block = $("[data-survey-block='#{@current_block}']")
    $($block).velocity 'scroll', 
      duration: scroll_duration
      easing: scroll_easing
      offset: -200
      begin: =>
        $(@survey_blocks[@current_block])
          .removeClass 'highlight' 
          .attr 'style', ''
      complete: =>
        @animating = false
        @focusField()
    if $block.hasClass 'not-seen'
      $block.velocity {opacity: [1, 0], translateY: ['0%', '100%']},
        queue: false
        complete: =>
          $block.removeClass 'not-seen disabled'

  nextBlock: ->
    return if @animating
    toIndex = @current_block + 1
    $block = $("[data-survey-block='#{toIndex}']")
    
    $($block).velocity 'scroll', 
      duration: scroll_duration
      easing: scroll_easing
      offset: -200
      begin: =>
        $(@survey_blocks[@current_block])
          .removeClass 'highlight' 
          .attr 'style', ''
        @updateProgress(toIndex)
      complete: =>
        @animating = false
        @current_block = toIndex
        @focusField()
    if $block.hasClass 'not-seen'
      $block.velocity {opacity: [1, 0], translateY: ['0%', '100%']},
        queue: false
        complete: =>
          $block.removeClass 'not-seen'

  prevBlock: (e) ->
    e.preventDefault()
    return if @animating
    toIndex = @current_block - 1
    $(@survey_blocks[toIndex]).velocity 'scroll', 
      duration: scroll_duration
      easing: scroll_easing
      offset: -200
      begin: =>
        @animating = true
      complete: =>  
        @animating = false
        @current_block = toIndex
        @focusField()

  validateCurrentQuestion: (e) ->
    e.preventDefault()

    if $(e.target).closest('.button').data('no-validate')?
      @nextBlock(e)
      return

    $block = $(@survey_blocks[@current_block])
    $errorsEl = $block.find('[data-errors]')
    question_group_index = @currentQuestionGroupIndex()
    $form = if question_group_index? then $(@$survey_form[question_group_index]) else @$survey_form
    validation = $form.parsley({uiEnabled: false}).validate group: "#{$block.data 'parsley-group'}"
    if $block.find("[data-required-checkbox='true']").length
      if $block.find('input[type="checkbox"]:checked').length is 0
        validation = false

    if validation is true
      $errorsEl.empty()
      @removeNextButton(e)
      @nextBlock(e)
    else
      @handleRequiredQuestion()

  currentQuestionGroupIndex: ->
    $(@survey_blocks[@current_block]).find('[data-question-group]').first().data 'question-group'

  setFormValidationSections: ->
    @survey_blocks.each (i, block) => 
      $block = $(block)
      $block.attr 'data-parsley-group', "block#{i}"
      $block.find(':input').attr 'data-parsley-group', "block#{i}"

  handleRequiredQuestion: ->
    $(@survey_blocks[@current_block]).addClass 'highlight'

  focusField: ->
    $(@survey_blocks[@current_block]).find('input, textarea').first().focus()

  updateProgress: (index) ->
    width = "#{(index / (@survey_blocks.length - 1)) * 100}%"
    @survey_progress.css 'width', width

  removeNextButton: ({target}) ->
    return unless target?
    $el = $(target).closest '.button'
    if $el.hasClass 'button'
      $el.addClass 'hidden'

  initRangeSliders: ->
    
    getRulerRange = (min, max, step) ->
      range = ''
      i = 0
      while i <= max
        range += i + ' '
        i = i + step
      range

    $('input[type="range"]').each (i, slider) ->
      $ruler = $('<div class="rangeslider__ruler" />')
      $(slider).rangeslider
        polyfill: false
        rangeClass: 'rangeslider'
        disabledClass: 'rangeslider--disabled'
        horizontalClass: 'rangeslider--horizontal'
        verticalClass: 'rangeslider--vertical'
        fillClass: 'rangeslider__fill'
        handleClass: 'rangeslider__handle'
        onInit: ->
          $ruler[0].innerHTML = getRulerRange(this.min, this.max, this.step)
          this.$range.prepend $ruler
        onSlide: (position, value) ->
        onSlideEnd: (position, value) ->

  showThankYou: ->
    @$survey_form.addClass 'hidden'
    @$intro.addClass 'hidden'
    @$thank_you.velocity 'scroll', 
      duration: scroll_duration
      easing: scroll_easing
      offset: -200
      complete: =>
        @animating = false

    @$thank_you.velocity {opacity: [1, 0], translateY: ['0%', '20%']},
      queue: false

  toggleShowQuestionGroupTitle: ({target}) ->
    id = $(target).data 'show-title'
    checked = target.checked
    $.ajax
      url: "/surveys_question_group"
      method: "put"
      data: JSON.stringify({id: id, value: checked})
      dataType: 'json'
      contentType: 'application/json'
      success: (e) -> console.log 'success', e
      error: (e) -> console.log 'error', e

  initConditionals: ->
    $('[data-conditional-question]').each (i, question) =>
      $(question).addClass 'hidden'
      { question_id, operator, value } = Utils.parseConditionalString $(question).data 'conditional-question'

      if @survey_conditionals[question_id]?
        @survey_conditionals[question_id].children.push question
      else
        @survey_conditionals[question_id] = {}
        @survey_conditionals[question_id].children = [question]

      @survey_conditionals[question_id][value] = question if value?

      switch operator
        when '*presence'
          @conditionalPresenceListeners(question_id, question)
        when '<', '>'
          @conditionalComparisonListeners(question_id, operator, question)
        else
          @conditionalAnswerListeners(question_id, question)

  conditionalAnswerListeners: (id, operator) ->
    # @survey_conditionals[id].operator = operator
    $("#question_#{id} input, #question_#{id} select").on 'change', ({target}) =>
      value = $(target).val()
      @handleParentConditionalChange value, @survey_conditionals[id], $("#question_#{id}").parents('.block')

  conditionalComparisonListeners: (id, operator) ->
    $("#question_#{id} input").on 'change', ({target}) =>
      console.log target.value, operator

  conditionalPresenceListeners: (id, question) ->
    @survey_conditionals[id].present = false
    @survey_conditionals[id].question = question
    $("#question_#{id} textarea").on 'keyup', ({target}) =>
      @handleParentPresenceConditionalChange 
        present: target.value.length
        conditional_group: @survey_conditionals[id]
        $parent: $("#question_#{id}").parents('.block')

  handleParentConditionalChange: (value, conditional_group, $parent) ->
    console.log value
    # Reset all conditional question blocks
    conditional_group.children.map (question) ->
      $(question)
        .removeAttr 'style'
        .addClass 'hidden not-seen disabled'

    conditional = undefined
    if Array.isArray value
      value.map (v) => 
        if conditional_group[v]?
          conditional = conditional_group[v]
    else
      conditional = conditional_group[value]

    if conditional?
      $(conditional)
        .removeClass 'hidden'
        .attr 'data-survey-block', ''
      @indexBlocks =>
        @current_block = parseInt $parent.data 'survey-block'
      $parent.find('.survey__next.hidden').removeClass 'hidden'

  handleParentPresenceConditionalChange: (params) ->
    { present, conditional_group, $parent } = params;
    $question = $(conditional_group.question)
    if present and !conditional_group.present
      conditional_group.present = true
      $question
        .removeClass 'hidden'
        .attr 'data-survey-block', ''

    else if !present and conditional_group.present
      conditional_group.present = false
      $question
        .removeAttr 'style'
        .addClass 'hidden not-seen disabled'
        .find('textarea').val ''
    else
      # console.log @current_block

    $parent.find('.survey__next.hidden').removeClass 'hidden'

    @indexBlocks()
    @current_block = $parent.data 'survey-block'
    @updateCurrentBlock()


module.exports = Survey 