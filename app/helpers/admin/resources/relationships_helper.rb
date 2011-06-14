module Admin::Resources::RelationshipsHelper

  def setup_relationship(field)
    @field = field
    @model_to_relate = @resource.reflect_on_association(field.to_sym).class_name.typus_constantize
    @model_to_relate_as_resource = @model_to_relate.to_resource
    @reflection = @resource.reflect_on_association(field.to_sym)
    @association_name = @reflection.name.to_s
  end

  def typus_form_has_many(field)
    setup_relationship(field)

    options = @reflection.through_reflection ? {} : { @reflection.foreign_key => @item.id }

    count_items_to_relate = @model_to_relate.order(@model_to_relate.typus_order_by).count - @item.send(field).count

    build_pagination

    # If we are on a through_reflection set the association name!
    @resource_actions = if @reflection.through_reflection
                          [["Edit", { :action => "edit", :layout => 'admin/headless' }, { :class => 'iframe' }],
                           ["Unrelate", { :resource_id => @item.id,
                                          :resource => @resource.model_name,
                                          :action => "unrelate",
                                          :association_name => @association_name},
                                        { :confirm => "Unrelate?" } ]]
                        else
                          [["Edit", { :action => "edit", :layout => 'admin/headless' }, { :class => 'iframe' }],
                           ["Trash", { :resource_id => @item.id,
                                       :resource => @resource.model_name,
                                       :action => "destroy" },
                                     { :confirm => "Trash?" } ]]
                         end

    locals = { :association_name => @association_name, :add_new => build_add_new(options), :table => build_relationship_table }
    render "admin/templates/has_n", locals
  end

  def typus_form_has_and_belongs_to_many(field)
    setup_relationship(field)
    build_pagination

    # TODO: Find a cleaner way to add these actions ...
    @resource_actions = [["Edit", { :action => "edit", :layout => 'admin/headless' }, { :class => 'iframe' }],
                         ["Unrelate", { :resource_id => @item.id,
                                        :resource => @resource.model_name,
                                        :action => "unrelate"},
                                      { :confirm =>"Unrelate?" }]]

    locals = { :association_name => @association_name, :add_new => build_add_new, :table => build_relationship_table }
    render "admin/templates/has_n", locals
  end

  def build_pagination
    items_per_page = @model_to_relate.typus_options_for(:per_page)
    data = @item.send(@field).order(@model_to_relate.typus_order_by).where(set_conditions)
    @items = data.page(params[:page]).per(items_per_page)
  end

  def build_relationship_table
    build_list(@model_to_relate,
               @model_to_relate.typus_fields_for(:relationship),
               @items,
               @model_to_relate_as_resource,
               {},
               @reflection.macro,
               @association_name)
  end

  def build_add_new(options = {})
    default_options = { :controller => "/admin/#{@model_to_relate.to_resource}",
                        :action => "index",
                        :resource => @resource.model_name,
                        :layout => 'admin/headless',
                        :resource_id => @item.id,
                        :resource_action => 'relate',
                        :return_to => request.path }

    if set_condition && admin_user.can?("create", @model_to_relate)
      link_to Typus::I18n.t("Add New"), default_options.merge(options), { :class => "iframe" }
    end
  end

  def set_condition
    if @resource.typus_user_id? && admin_user.is_not_root?
      admin_user.owns?(@item)
    else
      true
    end
  end

  def set_conditions
    if @model_to_relate.typus_options_for(:only_user_items) && admin_user.is_not_root?
      { Typus.user_foreign_key => admin_user }
    end
  end

  def typus_form_has_one(field)
    setup_relationship(field)

    @items = Array.new
    if item = @item.send(field)
      @items << item
    end

    # TODO: Find a cleaner way to add these actions ...
    @resource_actions = [["Edit", {:action=>"edit"}, {}],
                         ["Trash", { :resource_id => @item.id, :resource => @resource.model_name, :action => "destroy" }, { :confirm => "Trash?" }]]

    options = { :resource_id => nil, @reflection.foreign_key => @item.id }

    render "admin/templates/has_one",
           :association_name => @association_name,
           :add_new => @items.empty? ? build_add_new(options) : nil,
           :table => build_relationship_table
  end

  def typus_belongs_to_field(attribute, form)
    association = @resource.reflect_on_association(attribute.to_sym)

    related = if defined?(set_belongs_to_context)
                set_belongs_to_context.send(attribute.pluralize.to_sym)
              else
                association.class_name.typus_constantize
              end
    related_fk = association.foreign_key

    # TODO: Use the build_add_new method.
    if admin_user.can?('create', related)
      options = { :controller => "/admin/#{related.to_resource}",
                  :action => 'new',
                  :resource => @resource.model_name,
                  :layout => 'admin/headless' }
      # Pass the resource_id only to edit/update because only there is where
      # the record actually exists.
      options.merge!(:resource_id => @item.id) if %w(edit update).include?(params[:action])
      message = link_to Typus::I18n.t("Add New"), options, { :class => 'iframe' }
    end

    # Set the template.
    template = if Typus.autocomplete && (related.respond_to?(:roots) || !(related.count > Typus.autocomplete))
                 "admin/templates/belongs_to"
               else
                 "admin/templates/belongs_to_with_autocomplete"
               end

    # Set the values.
    values = if related.respond_to?(:roots)
               expand_tree_into_select_field(related.roots, related_fk)
             elsif Typus.autocomplete && !(related.count > Typus.autocomplete)
               related.order(related.typus_order_by).map { |p| [p.to_label, p.id] }
             end

    render template,
           :association => association,
           :resource => @resource,
           :attribute => attribute,
           :form => form,
           :related_fk => related_fk,
           :related => related,
           :message => message,
           :label_text => @resource.human_attribute_name(attribute),
           :values => values,
           :html_options => { :disabled => attribute_disabled?(attribute) },
           :options => { :include_blank => true }
  end

end