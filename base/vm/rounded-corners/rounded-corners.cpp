#include <wayfire/view-transform.hpp>
#include <wayfire/opengl.hpp>
#include <wayfire/plugin.hpp>
#include <wayfire/signal-definitions.hpp>
#include <wayfire/toplevel-view.hpp>
#include <wayfire/scene.hpp>
#include <wayfire/scene-render.hpp>
#include <wayfire/option-wrapper.hpp>
#include <wayfire/region.hpp>

namespace rounded_corners
{
    const std::string vertex_source = R"(
#version 100
attribute mediump vec2 position;
varying mediump vec2 fposition;

uniform mat4 matrix;

void main() {
    gl_Position = matrix * vec4(position, 0.0, 1.0);
    fposition = position;
})";

    const std::string frag_source = R"(
#version 100
@builtin_ext@

varying mediump vec2 fposition;
@builtin@

// Top left corner
uniform mediump vec2 top_left;

// Top left corner with shadows included
uniform mediump vec2 full_top_left;

// Bottom right corner
uniform mediump vec2 bottom_right;

// Bottom right corner with shadows included
uniform mediump vec2 full_bottom_right;

// Rounding radius
uniform mediump float radius;

// Edge softness
uniform mediump float edge_softness;

// Border thickness
uniform mediump float border_size;

// Border color
uniform mediump vec4 border_color;

// Shadow softness
uniform mediump float shadow_softness;

// Shadow margin (space around the window reserved for the shadow)
uniform mediump float shadow_margin_u;

// Shadow color
uniform mediump vec4 shadow_color;

// rounded box with a smooth "squircle" corner: the corner is a super-ellipse (p-norm), so the curvature
// grows gradually instead of jumping at the end of a circle arc
mediump float rect_sdf(mediump vec2 center, mediump vec2 size, mediump float radius)
{
    mediump vec2 q = abs(center) - size + radius;
    mediump vec2 qp = max(q, 0.0);
    mediump float n = 4.0;
    mediump float corner = pow(pow(qp.x, n) + pow(qp.y, n), 1.0 / n);
    return corner + min(max(q.x, q.y), 0.0) - radius;
}

void main()
{
    // Get the pixel color
    highp vec2 uv = (fposition - full_top_left) / (full_bottom_right - full_top_left);
    uv.y = 1.0 - uv.y;
    highp vec4 pixel_color = get_pixel(uv);

    // Calculate data for sdf and alphas
    mediump vec2 size = bottom_right - top_left;
    mediump vec2 half_size = size / 2.0;
    mediump vec2 center = top_left + size / 2.0;
    mediump float distance = rect_sdf(fposition - top_left - half_size, half_size - shadow_margin_u, radius);
    mediump float smoothed_alpha = 1.0 - smoothstep(0.0, edge_softness * 2.0, distance);
    
    // Border pass
    if (border_size > 0.0)
    {
        mediump float border_alpha = 1.0 - smoothstep(max(0.0, border_size - (edge_softness * 2.0)), border_size, abs(distance));
        pixel_color = mix(pixel_color, border_color, border_alpha);
    }

    // Shadow pass
    highp vec4 before_shadow = mix(vec4(0.0, 0.0, 0.0, 0.0), pixel_color, smoothed_alpha);
    mediump float shadow_alpha = 1.0 - smoothstep(0.0, shadow_softness, distance);
    gl_FragColor = mix(before_shadow, shadow_color, shadow_alpha - smoothed_alpha);
})";

    glm::vec4 color_to_vec4(wf::color_t color)
    {
        return glm::vec4(color.r, color.g, color.b, color.a);
    }

    class rounded_corners_node_t : public wf::scene::view_2d_transformer_t
    {
    private:
        wayfire_toplevel_view view;
        OpenGL::program_t program;
        std::vector<GLfloat> vertex_data;
        GLfloat radius;
        GLfloat border_size;
        glm::vec4 border_color;
        int shadow_margin;
        GLfloat shadow_softness;
        glm::vec4 shadow_color;

    public:
        rounded_corners_node_t(wayfire_toplevel_view view, int radius, int border_size, wf::color_t border_color, int shadow_softness, int shadow_margin, wf::color_t shadow_color) : wf::scene::view_2d_transformer_t(view)
        {
            this->view = view;
            this->radius = radius;
            this->border_size = border_size;
            this->border_color = color_to_vec4(border_color);
            this->shadow_softness = shadow_softness;
            this->shadow_margin = shadow_margin;
            this->shadow_color = color_to_vec4(shadow_color);

            wf::gles::run_in_context([&]
            {
                program.compile(vertex_source, frag_source);
            });
        }

        void update(int radius, int border_size, wf::color_t border_color, int shadow_softness, int shadow_margin, wf::color_t shadow_color)
        {
            this->radius = radius;
            this->border_size = border_size;
            this->border_color = color_to_vec4(border_color);
            this->shadow_softness = shadow_softness;
            this->shadow_margin = shadow_margin;
            this->shadow_color = color_to_vec4(shadow_color);
            view->damage();
        }

        std::string stringify() const override
        {
            return "rounded-corners";
        }

        wf::geometry_t get_bounding_box() override {
            auto box = wf::scene::view_2d_transformer_t::get_bounding_box();
            if (view->get_geometry() == box)
            {
                return wf::geometry_t {
                    .x = box.x - shadow_margin,
                    .y = box.y - shadow_margin,
                    .width = box.width + shadow_margin * 2,
                    .height = box.height + shadow_margin * 2,
                };
            }
            return box;
        }

        void gen_render_instances(std::vector<wf::scene::render_instance_uptr> &instances,
                                  wf::scene::damage_callback push_damage, wf::output_t *shown_on) override
        {
            class rounded_corners_render_instance_t : public wf::scene::transformer_render_instance_t<rounded_corners_node_t>
            {
            public:
                using transformer_render_instance_t::transformer_render_instance_t;

                void transform_damage_region(wf::regionf_t &damage) override
                {
                    damage |= self->get_bounding_box();
                }

                void render(const wf::scene::render_instruction_t &data) override
                {
                    auto src_tex = wf::gles_texture_t{get_texture(data.target.scale)};
                    data.pass->custom_gles_subpass(data.target, [&]
                    {
                        self->program.use(src_tex.type);
                        self->program.set_active_texture(src_tex);
                        self->upload_data();
                        self->program.uniformMatrix4f("matrix", wf::gles::render_target_orthographic_projection(data.target));
                        GL_CALL(glEnable(GL_BLEND));
                        GL_CALL(glBlendFunc(GL_ONE, GL_ONE_MINUS_SRC_ALPHA));
                        for (const auto &box : data.damage)
                        {
                            wf::gles::render_target_logic_scissor(data.target, box);
                            GL_CALL(glDrawArrays(GL_TRIANGLE_FAN, 0, 4));
                        }
                        GL_CALL(glDisable(GL_BLEND));
                        self->program.deactivate();
                    });
                }
            };

            auto uptr = std::make_unique<rounded_corners_render_instance_t>(this, push_damage, shown_on);
            if (uptr->has_instances())
            {
                instances.push_back(std::move(uptr));
            }
        }

        void upload_data()
        {
            wf::geometry_t src_box = wf::scene::view_2d_transformer_t::get_bounding_box();
            auto geometry = view->get_geometry();
            float x = geometry.x - shadow_margin, y = geometry.y - shadow_margin,
                  w = geometry.width + shadow_margin * 2, h = geometry.height + shadow_margin * 2;

            vertex_data = {
                x,
                y + h,
                x + w,
                y + h,
                x + w,
                y,
                x,
                y,
            };

            program.attrib_pointer("position", 2, 0, vertex_data.data(), GL_FLOAT);

            program.uniform2f("top_left", x, y);
            program.uniform2f("bottom_right", x + w, y + h);
            program.uniform2f("full_top_left", src_box.x, src_box.y);
            program.uniform2f("full_bottom_right",
                              src_box.x + src_box.width, src_box.y + src_box.height);

            program.uniform1f("radius", radius);
            program.uniform1f("edge_softness", 1.0f);
            program.uniform1f("border_size", border_size);
            program.uniform4f("border_color", border_color);
            program.uniform1f("shadow_softness", shadow_softness);
            program.uniform1f("shadow_margin_u", (float)shadow_margin);
            program.uniform4f("shadow_color", shadow_color);
        }
    };

    class wayfire_rounded_corners_t : public wf::plugin_interface_t
    {
    private:
        wf::option_wrapper_t<int> radius{"rounded-corners/radius"};
        wf::option_wrapper_t<int> border_size{"rounded-corners/border_size"};
        wf::option_wrapper_t<wf::color_t> border_color{"rounded-corners/border_color"};
        wf::option_wrapper_t<int> shadow_softness{"rounded-corners/shadow_softness"};
        wf::option_wrapper_t<int> shadow_margin{"rounded-corners/shadow_margin"};
        wf::option_wrapper_t<wf::color_t> shadow_color{"rounded-corners/shadow_color"};

        wf::config::option_base_t::updated_callback_t on_setting_changed = [=]()
        {
            update_all();
        };

        wf::signal::connection_t<wf::view_mapped_signal> on_view_mapped = [=](wf::view_mapped_signal *ev)
        {
            auto toplevel = wf::toplevel_cast(ev->view);
            if (!toplevel)
            {
                return;
            }
            if (!disable_cutout_state(toplevel))
            {
                ensure_transformer(toplevel);
            }
            toplevel->connect(&on_tiled);
            toplevel->connect(&on_fullscreen);
        };

        wf::signal::connection_t<wf::view_tiled_signal> on_tiled = [=](wf::view_tiled_signal *ev)
        {
            if (!ev->view)
            {
                return;
            }
            update_cutout(ev->view);
        };

        wf::signal::connection_t<wf::view_fullscreen_signal> on_fullscreen = [=](wf::view_fullscreen_signal *ev)
        {
            if (!ev->view)
            {
                return;
            }
            update_cutout(ev->view);
        };

        std::shared_ptr<rounded_corners_node_t> ensure_transformer(wayfire_toplevel_view view)
        {
            auto tmgr = view->get_transformed_node();
            auto tr = tmgr->get_transformer<rounded_corners_node_t>("rounded-corners");
            if (!tr)
            {
                tr = std::make_shared<rounded_corners_node_t>(view, radius, border_size, border_color, shadow_softness, shadow_margin, shadow_color);
                tmgr->add_transformer(tr, wf::TRANSFORMER_2D - 1, "rounded-corners");
            }
            return tr;
        }

        void update_all()
        {
            for (auto &view : wf::get_core().get_all_views())
            {
                auto toplevel = wf::toplevel_cast(view);
                if (toplevel && !disable_cutout_state(toplevel))
                {
                    ensure_transformer(toplevel)->update(radius, border_size, border_color, shadow_softness, shadow_margin, shadow_color);
                }
            }
        }

        void update_cutout(wayfire_toplevel_view view)
        {
            if (disable_cutout_state(view))
            {
                view->get_transformed_node()->rem_transformer<rounded_corners_node_t>("rounded-corners");
            }
            else
            {
                ensure_transformer(view);
            }
        }

        bool disable_cutout_state(wayfire_toplevel_view view)
        {
            return view->pending_fullscreen() || view->pending_tiled_edges() == wf::TILED_EDGES_ALL;
        }

    public:
        void init() override
        {
            for (auto &view : wf::get_core().get_all_views())
            {
                auto toplevel = wf::toplevel_cast(view);
                if (toplevel)
                {
                    update_cutout(toplevel);
                }
            }
            radius.set_callback(on_setting_changed);
            border_size.set_callback(on_setting_changed);
            border_color.set_callback(on_setting_changed);
            shadow_softness.set_callback(on_setting_changed);
            shadow_margin.set_callback(on_setting_changed);
            shadow_color.set_callback(on_setting_changed);
            wf::get_core().connect(&on_view_mapped);
        }

        void fini() override
        {
            for (auto &view : wf::get_core().get_all_views())
            {
                view->get_transformed_node()->rem_transformer<rounded_corners_node_t>("rounded-corners");
            }
            wf::get_core().disconnect(&on_view_mapped);
        }
    };
}

DECLARE_WAYFIRE_PLUGIN(rounded_corners::wayfire_rounded_corners_t);
