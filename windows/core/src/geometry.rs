/// A point in device-independent pixels from a monitor's top left, y counting down.
#[derive(Clone, Copy, Debug, PartialEq, Default)]
pub struct Point {
    pub x: f32,
    pub y: f32,
}

impl Point {
    pub const fn new(x: f32, y: f32) -> Self {
        Point { x, y }
    }

    pub fn distance(self, other: Point) -> f32 {
        ((other.x - self.x).powi(2) + (other.y - self.y).powi(2)).sqrt()
    }

    /// This point moved onto the nearest of the eight 45 degree directions from `origin`,
    /// projected rather than rotated, so a drag along an axis keeps its exact length.
    pub fn snapped45(self, origin: Point) -> Point {
        let dx = self.x - origin.x;
        let dy = self.y - origin.y;
        let (ax, ay) = (dx.abs(), dy.abs());
        let tan22 = 0.414_213_56;
        if ay <= ax * tan22 {
            return Point::new(origin.x + dx, origin.y);
        }
        if ax <= ay * tan22 {
            return Point::new(origin.x, origin.y + dy);
        }
        let diagonal = (ax + ay) / 2.0;
        Point::new(origin.x + diagonal.copysign(dx), origin.y + diagonal.copysign(dy))
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Default)]
pub struct Rect {
    pub x: f32,
    pub y: f32,
    pub width: f32,
    pub height: f32,
}

/// How far along a stroke, in points, a point is pulled towards its neighbours: at least the
/// first, more where a quick stroke spaced its points out, up to the second.
const REACH: (f32, f32) = (3.0, 5.0);

/// A freehand stroke as a smooth curve, for the pen and the highlighter, as cubic Bezier
/// segments: each is the two control points and the end. The curve starts at the first point.
///
/// The pointer reports whole points, so a slow line arrives as a staircase, and a quick one
/// zigzags by up to a point either way. Each point is pulled towards its neighbours within a few
/// points of length either side, which irons that out and leaves a turn the hand made in place.
/// The curve then runs through the middle of each pair of points rather than through the points,
/// so it has no corner anywhere. Reported: drawn through every point, strokes came out rough,
/// with a kink at every step.
pub fn smooth(points: &[Point]) -> Vec<(Point, Point, Point)> {
    if points.len() < 2 {
        return Vec::new();
    }
    let line = |from: Point, to: Point| {
        let third = |f: f32| Point::new(from.x + (to.x - from.x) * f, from.y + (to.y - from.y) * f);
        (third(1.0 / 3.0), third(2.0 / 3.0), to)
    };
    if points.len() == 2 {
        return vec![line(points[0], points[1])];
    }
    let smooth = smoothed(points);
    let mut segments = Vec::with_capacity(smooth.len() - 1);
    let mut start = smooth[0];
    for pair in smooth[1..].windows(2) {
        let (control, next) = (pair[0], pair[1]);
        let end = Point::new((control.x + next.x) / 2.0, (control.y + next.y) / 2.0);
        // A quadratic curve, as the cubic Direct2D takes.
        let toward = |from: Point| Point::new(from.x + (control.x - from.x) * 2.0 / 3.0, from.y + (control.y - from.y) * 2.0 / 3.0);
        segments.push((toward(start), toward(end), end));
        start = end;
    }
    segments.push(line(start, smooth[smooth.len() - 1]));
    segments
}

/// Every point but the first and last moved to the average of those near it along the stroke,
/// the nearest counting most.
fn smoothed(points: &[Point]) -> Vec<Point> {
    let mut along = vec![0.0f32];
    for pair in points.windows(2) {
        along.push(along[along.len() - 1] + pair[0].distance(pair[1]));
    }
    let mut result = points.to_vec();
    let mut low = 0;
    for index in 1..points.len() - 1 {
        let reach = ((along[index + 1] - along[index - 1]) / 2.0).clamp(REACH.0, REACH.1);
        let span = reach * 3.0;
        while along[index] - along[low] > span {
            low += 1;
        }
        let (mut x, mut y, mut total) = (0.0, 0.0, 0.0);
        let mut near = low;
        while near < points.len() && along[near] - along[index] <= span {
            let gap = along[near] - along[index];
            let weight = (-gap * gap / (2.0 * reach * reach)).exp();
            x += points[near].x * weight;
            y += points[near].y * weight;
            total += weight;
            near += 1;
        }
        result[index] = Point::new(x / total, y / total);
    }
    result
}

/// A straight arrow whose body widens from a thin tail to a swept back head, as Tinysnap draws
/// it: the outline's corners, to be filled and stroked with round joins.
pub fn arrow_outline(tail: Point, tip: Point, width: f32) -> Vec<Point> {
    let length = tail.distance(tip);
    if length <= 0.0 {
        return Vec::new();
    }
    let (ux, uy) = ((tip.x - tail.x) / length, (tip.y - tail.y) / length);
    let (nx, ny) = (-uy, ux);
    let head = (length * 0.5).min(width * 4.2);
    let head_half = head * 0.62;
    let neck_half = (width * 0.6).min(head_half * 0.5);
    let tail_half = width * 0.18;
    let base = Point::new(tip.x - ux * head, tip.y - uy * head);
    // The barbs sit a little behind the neck, which sweeps the head back.
    let barb = Point::new(base.x - ux * head * 0.12, base.y - uy * head * 0.12);
    let at = |point: Point, offset: f32| Point::new(point.x + nx * offset, point.y + ny * offset);
    vec![
        at(tail, tail_half),
        at(base, neck_half),
        at(barb, head_half),
        tip,
        at(barb, -head_half),
        at(base, -neck_half),
        at(tail, -tail_half),
    ]
}

/// The laser pointer's trail: where the pointer has been in the last 0.7 s, each point fading as
/// it ages. Nothing of it is kept.
#[derive(Default)]
pub struct LaserTrail {
    points: Vec<(Point, f64)>,
}

impl LaserTrail {
    pub const FADE: f64 = 0.7;

    pub fn add(&mut self, point: Point, time: f64) {
        self.points.push((point, time));
    }

    /// The points still showing at `now`, oldest first, with how opaque each is.
    pub fn visible(&self, now: f64) -> Vec<(Point, f32)> {
        self.points
            .iter()
            .filter_map(|&(point, time)| {
                let age = now - time;
                (age < Self::FADE).then(|| (point, (1.0 - age.max(0.0) / Self::FADE) as f32))
            })
            .collect()
    }

    pub fn prune(&mut self, now: f64) {
        self.points.retain(|&(_, time)| now - time < Self::FADE);
    }

    /// Nothing left to fade, so the screen need not be redrawn until the pointer moves again.
    pub fn is_idle(&self, now: f64) -> bool {
        self.visible(now).is_empty()
    }
}

/// The zoom lens: a circle on the pointer showing the screen under it magnified.
pub struct Lens;

impl Lens {
    pub const RADIUS: f32 = 120.0;
    pub const MIN: f32 = 1.5;
    pub const MAX: f32 = 6.0;

    /// The magnification after a scroll of `notches`, up for more, 1.08 times a notch: from 2x to the
    /// most is about fifteen notches.
    pub fn magnification(current: f32, notches: f32) -> f32 {
        (current * 1.08_f32.powf(notches)).clamp(Self::MIN, Self::MAX)
    }

    /// The part of the screen the lens shows, centred on the pointer.
    pub fn source(center: Point, radius: f32, magnification: f32) -> Rect {
        let half = radius / magnification;
        Rect { x: center.x - half, y: center.y - half, width: half * 2.0, height: half * 2.0 }
    }
}

/// The spotlight: every monitor dimmed except a circle round the pointer.
pub struct Spotlight;

impl Spotlight {
    pub const RADIUS: f32 = 140.0;

    /// The radius after a scroll of `notches`, up for bigger, 10 pixels a notch, kept between 60
    /// and 600.
    pub fn radius(current: f32, notches: f32) -> f32 {
        (current + notches * 10.0).clamp(60.0, 600.0)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_smooth_stroke_ends_where_the_pointer_did() {
        let points = [Point::new(0.0, 0.0), Point::new(10.0, 5.0), Point::new(20.0, 0.0), Point::new(30.0, 8.0)];
        let segments = smooth(&points);
        assert_eq!(segments.len(), 3);
        assert_eq!(segments.last().unwrap().2, Point::new(30.0, 8.0));
    }

    /// Which way the stroke heads along each point of its length.
    fn directions(points: &[Point]) -> Vec<f32> {
        let mut line = vec![points[0]];
        for (one, two, end) in smooth(points) {
            let start = *line.last().unwrap();
            for step in 1..=32 {
                let t = step as f32 / 32.0;
                let u = 1.0 - t;
                let at = |a: f32, b: f32, c: f32, d: f32| u * u * u * a + 3.0 * u * u * t * b + 3.0 * u * t * t * c + t * t * t * d;
                line.push(Point::new(at(start.x, one.x, two.x, end.x), at(start.y, one.y, two.y, end.y)));
            }
        }
        // Every point of length, so a dense stretch weighs no more than a sparse one.
        let mut even = vec![line[0]];
        let mut travelled = 0.0;
        for pair in line.windows(2) {
            let length = pair[0].distance(pair[1]);
            if length == 0.0 {
                continue;
            }
            let mut at = 1.0 - travelled;
            while at <= length {
                let f = at / length;
                even.push(Point::new(pair[0].x + (pair[1].x - pair[0].x) * f, pair[0].y + (pair[1].y - pair[0].y) * f));
                at += 1.0;
            }
            travelled = length - (at - 1.0);
        }
        even.windows(2).map(|pair| (pair[1].y - pair[0].y).atan2(pair[1].x - pair[0].x)).collect()
    }

    fn turns(angles: &[f32]) -> Vec<f32> {
        let tau = std::f32::consts::TAU;
        angles.windows(2).map(|pair| (pair[1] - pair[0] + tau / 2.0).rem_euclid(tau) - tau / 2.0).collect()
    }

    /// The pointer reports whole points, so a slow line arrives as a staircase. Reported: strokes
    /// came out rough, with a kink at every step.
    #[test]
    fn a_slow_straight_line_comes_out_straight() {
        let points: Vec<Point> = (0..=120).map(|x| Point::new(x as f32, (x as f32 * 0.3).round())).collect();
        let slope = 0.3f32.atan2(1.0);
        let worst = directions(&points).iter().map(|angle| (angle - slope).abs()).fold(0.0, f32::max);
        assert!(worst < 3f32.to_radians(), "{}", worst.to_degrees());
    }

    /// A circle drawn slowly turns evenly, a little each point, with no corner anywhere.
    #[test]
    fn a_slow_circle_turns_evenly() {
        let points: Vec<Point> = (0..=220)
            .map(|step| {
                let angle = (step as f32 * 1.5).to_radians();
                Point::new((100.0 + 40.0 * angle.cos()).round(), (100.0 + 40.0 * angle.sin()).round())
            })
            .collect();
        let worst = turns(&directions(&points)).iter().map(|turn| turn.abs()).fold(0.0, f32::max);
        assert!(worst < 4f32.to_radians(), "{}", worst.to_degrees());
    }

    /// A quick stroke reports a point every several, each off by up to a point. The wave bends one
    /// way and then the other, without wobbling in between.
    #[test]
    fn a_quick_wave_bends_without_wobbling() {
        let points: Vec<Point> = (0..=60)
            .map(|index| {
                let t = index as f32 / 60.0;
                let wobble = (index as f32 * 12.9898).sin() * 0.35;
                Point::new((240.0 + 140.0 * t + wobble).round(), (260.0 + 60.0 * (t * 3.0 * std::f32::consts::PI).sin() - wobble).round())
            })
            .collect();
        let turns: Vec<f32> = turns(&directions(&points)).into_iter().filter(|turn| turn.abs() > 0.5f32.to_radians()).collect();
        let flips = turns.windows(2).filter(|pair| (pair[0] < 0.0) != (pair[1] < 0.0)).count();
        assert!(flips <= 2, "{flips}");
    }

    #[test]
    fn the_arrow_ends_at_its_tip() {
        let outline = arrow_outline(Point::new(0.0, 0.0), Point::new(100.0, 0.0), 6.0);
        assert_eq!(outline.len(), 7);
        assert_eq!(outline[3], Point::new(100.0, 0.0));
        assert!(arrow_outline(Point::new(5.0, 5.0), Point::new(5.0, 5.0), 6.0).is_empty());
    }

    #[test]
    fn the_trail_fades_over_seven_tenths_of_a_second() {
        let mut trail = LaserTrail::default();
        trail.add(Point::new(0.0, 0.0), 10.0);
        trail.add(Point::new(5.0, 0.0), 10.35);
        let visible = trail.visible(10.35);
        assert_eq!(visible.len(), 2);
        assert!((visible[0].1 - 0.5).abs() < 0.001);
        assert_eq!(visible[1].1, 1.0);
    }

    #[test]
    fn points_older_than_the_fade_are_gone() {
        let mut trail = LaserTrail::default();
        trail.add(Point::new(0.0, 0.0), 10.0);
        trail.add(Point::new(5.0, 0.0), 10.5);
        trail.prune(10.8);
        assert_eq!(trail.visible(10.8).iter().map(|v| v.0).collect::<Vec<_>>(), vec![Point::new(5.0, 0.0)]);
        assert!(!trail.is_idle(10.8));
        assert!(trail.is_idle(11.3));
    }

    #[test]
    fn zoom_stays_between_one_and_a_half_and_six() {
        assert_eq!(Lens::magnification(2.0, 100.0), 6.0);
        assert_eq!(Lens::magnification(2.0, -100.0), 1.5);
        assert!(Lens::magnification(2.0, 1.0) > 2.0);
    }

    #[test]
    fn the_lens_shows_the_square_round_the_pointer() {
        let source = Lens::source(Point::new(500.0, 300.0), 120.0, 2.0);
        assert_eq!(source, Rect { x: 440.0, y: 240.0, width: 120.0, height: 120.0 });
    }

    #[test]
    fn the_spotlight_stays_between_60_and_600() {
        assert_eq!(Spotlight::radius(140.0, 1000.0), 600.0);
        assert_eq!(Spotlight::radius(140.0, -1000.0), 60.0);
    }

    /// Reported on the Mac: scrolling sized the spotlight and the lens aggressively. A notch is now a
    /// gentle step.
    #[test]
    fn a_notch_is_a_gentle_step() {
        assert_eq!(Spotlight::radius(140.0, 1.0), 150.0);
        assert!((Lens::magnification(2.0, 1.0) - 2.16).abs() < 0.001);
    }

    #[test]
    fn shift_keeps_an_arrow_to_45_degrees() {
        let origin = Point::new(100.0, 100.0);
        assert_eq!(Point::new(200.0, 110.0).snapped45(origin), Point::new(200.0, 100.0));
        assert_eq!(Point::new(190.0, 210.0).snapped45(origin), Point::new(200.0, 200.0));
    }
}
