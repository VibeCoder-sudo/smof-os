// smooth-geometry : when a window gets a new size or place (tiling, maximize, snapping, moving it by a script) it does not jump. The window is shown
// at its old rectangle at first and glides to the new one with an ease out curve, stretched by the graphics card. The client draws at its new size
// at once, so the animation does not depend on how fast the program redraws. Small changes (dragging with the mouse) are left alone.
#include <wayfire/plugin.hpp>
#include <wayfire/view-transform.hpp>
#include <wayfire/signal-definitions.hpp>
#include <wayfire/toplevel-view.hpp>
#include <wayfire/scene.hpp>
#include <wayfire/render-manager.hpp>
#include <wayfire/output.hpp>
#include <wayfire/option-wrapper.hpp>
#include <wayfire/util/duration.hpp>
#include <chrono>
#include <cmath>
#include <map>
#include <memory>

namespace smooth_geometry
{
    class node_t : public wf::scene::view_2d_transformer_t
    {
      public:
        node_t(wayfire_toplevel_view view) : wf::scene::view_2d_transformer_t(view) {}
    };

    // ease out quart: fast at the start, a long soft landing
    static double ease(double x)
    {
        x = std::min(1.0, std::max(0.0, x));
        return 1.0 - std::pow(1.0 - x, 4.0);
    }

    struct anim_t
    {
        wayfire_toplevel_view view;
        wf::output_t *output = nullptr;
        std::shared_ptr<node_t> node;
        wf::geometry_t from, to;
        std::chrono::steady_clock::time_point t0;
        double duration_ms = 380;
        wf::effect_hook_t hook;
    };

    static wf::geometry_t lerp(wf::geometry_t a, wf::geometry_t b, double t)
    {
        return {
            std::round(a.x + (b.x - a.x) * t),
            std::round(a.y + (b.y - a.y) * t),
            std::max(1.0, std::round(a.width + (b.width - a.width) * t)),
            std::max(1.0, std::round(a.height + (b.height - a.height) * t))};
    }

    class plugin_t : public wf::plugin_interface_t
    {
        wf::option_wrapper_t<int> duration{"smooth-geometry/duration"};
        wf::option_wrapper_t<int> min_distance{"smooth-geometry/min_distance"};
        std::map<wf::view_interface_t*, std::unique_ptr<anim_t>> anims;
        std::map<wf::view_interface_t*, std::chrono::steady_clock::time_point> mapped_at;
        std::vector<std::unique_ptr<anim_t>> graveyard;       // finished animations are freed a little later, never from inside their own hook

        // where the window looks to be now
        wf::geometry_t current(const anim_t& a)
        {
            double t = std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - a.t0).count() / a.duration_ms;
            return lerp(a.from, a.to, ease(t));
        }

        void apply(anim_t& a, wf::geometry_t rect)
        {
            // the node scales around the centre of the window and then moves, so the rectangle is reached with a scale and a shift of the centres
            double cx_new = a.to.x + a.to.width / 2.0, cy_new = a.to.y + a.to.height / 2.0;
            double cx = rect.x + rect.width / 2.0, cy = rect.y + rect.height / 2.0;
            a.node->scale_x = (float)rect.width / (float)std::max(1.0, (double)a.to.width);
            a.node->scale_y = (float)rect.height / (float)std::max(1.0, (double)a.to.height);
            a.node->translation_x = (float)(cx - cx_new);
            a.node->translation_y = (float)(cy - cy_new);
        }

        void stop(wf::view_interface_t *v)
        {
            auto it = anims.find(v);
            if (it == anims.end()) return;
            auto& a = *it->second;
            if (a.output) a.output->render->rem_effect(&a.hook);
            a.view->get_transformed_node()->rem_transformer<node_t>("smof-smooth");
            if (a.output) a.output->render->damage_whole();       // the old rectangle must be painted over too
            graveyard.push_back(std::move(it->second));
            anims.erase(it);
        }

        void frame(wf::view_interface_t *v)
        {
            auto it = anims.find(v);
            if (it == anims.end()) return;
            auto& a = *it->second;
            double t = std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - a.t0).count() / a.duration_ms;
            if (t >= 1.0)
            {
                stop(v);
                return;
            }
            apply(a, current(a));
            if (a.output) { a.output->render->damage_whole(); a.output->render->schedule_redraw(); }
        }

        wf::signal::connection_t<wf::view_geometry_changed_signal> on_geometry = [=] (wf::view_geometry_changed_signal *ev)
        {
            graveyard.clear();
            auto view = ev->view;
            if (!view || !view->is_mapped() || !view->get_output()) return;
            auto *key = (wf::view_interface_t*)view.get();
            wf::geometry_t old_g = ev->old_geometry, new_g = view->get_geometry();
            if (old_g.width <= 1 || old_g.height <= 1) return;
            // a window that has only just appeared is placed by the open animation
            auto m = mapped_at.find(key);
            if (m != mapped_at.end() && std::chrono::steady_clock::now() - m->second < std::chrono::milliseconds(250)) return;
            if ((int)duration <= 0) return;

            wf::geometry_t from = old_g;
            auto it = anims.find(key);
            if (it != anims.end()) from = current(*it->second);          // carry on from where the window looks to be
            double d = std::max({std::fabs((double)from.x - new_g.x), std::fabs((double)from.y - new_g.y), std::fabs((double)from.width - new_g.width), std::fabs((double)from.height - new_g.height)});
            if (d < (double)(int)min_distance)
            {
                if (it != anims.end()) stop(key);
                return;
            }

            if (it == anims.end())
            {
                auto a = std::make_unique<anim_t>();
                a->view = view;
                a->output = view->get_output();
                a->node = std::make_shared<node_t>(view);
                view->get_transformed_node()->add_transformer(a->node, wf::TRANSFORMER_2D, "smof-smooth");
                auto *raw = a.get();
                a->hook = [=] () { frame(key); };
                a->output->render->add_effect(&a->hook, wf::OUTPUT_EFFECT_PRE);
                (void)raw;
                it = anims.emplace(key, std::move(a)).first;
            }
            auto& a = *it->second;
            a.from = from; a.to = new_g;
            a.t0 = std::chrono::steady_clock::now();
            a.duration_ms = std::min(1200.0, (double)duration * (0.6 + 0.4 * std::min(1.0, d / 400.0)));   // short hops are quicker
            apply(a, from);
            a.output->render->damage_whole();
            a.output->render->schedule_redraw();
        };

        wf::signal::connection_t<wf::view_mapped_signal> on_mapped = [=] (wf::view_mapped_signal *ev)
        {
            auto tl = wf::toplevel_cast(ev->view);
            if (!tl) return;
            mapped_at[(wf::view_interface_t*)tl.get()] = std::chrono::steady_clock::now();
            tl->connect(&on_geometry);
        };

        wf::signal::connection_t<wf::view_unmapped_signal> on_unmapped = [=] (wf::view_unmapped_signal *ev)
        {
            auto *key = (wf::view_interface_t*)ev->view.get();
            stop(key);
            mapped_at.erase(key);
        };

      public:
        void init() override
        {
            for (auto& v : wf::get_core().get_all_views())
            {
                auto tl = wf::toplevel_cast(v);
                if (tl) tl->connect(&on_geometry);
            }
            wf::get_core().connect(&on_mapped);
            wf::get_core().connect(&on_unmapped);
        }

        void fini() override
        {
            std::vector<wf::view_interface_t*> keys;
            for (auto& kv : anims) keys.push_back(kv.first);
            for (auto *k : keys) stop(k);
            graveyard.clear();
            wf::get_core().disconnect(&on_mapped);
            wf::get_core().disconnect(&on_unmapped);
            on_geometry.disconnect();
        }
    };
}

DECLARE_WAYFIRE_PLUGIN(smooth_geometry::plugin_t);
