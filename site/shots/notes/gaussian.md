# The Gaussian integral

*Notes for Thursday's reading group.*

The bell curve $e^{-x^2}$ has no elementary antiderivative, and yet the area under it
is known exactly:

$$
I = \int_{-\infty}^{\infty} e^{-x^2}\,dx = \sqrt{\pi}
$$

## The trick

Square it, and two integrals over a line become one over the plane. In polar
coordinates the plane is swept by circles:

$$
\begin{aligned}
I^2 &= \int_{-\infty}^{\infty}\!\int_{-\infty}^{\infty} e^{-(x^2+y^2)}\,dx\,dy \\
    &= \int_{0}^{2\pi}\!\int_{0}^{\infty} e^{-r^2}\,r\,dr\,d\theta \\
    &= 2\pi \cdot \tfrac{1}{2} = \pi
\end{aligned}
$$

> [!NOTE]
> The factor $r$ in $dx\,dy = r\,dr\,d\theta$ is what rescues us: unlike $e^{-x^2}$,
> the integrand $r e^{-r^2}$ has the antiderivative $-\tfrac{1}{2}e^{-r^2}$.

## Why it matters

The normal distribution's density

$$
f(x) = \frac{1}{\sigma\sqrt{2\pi}} \exp\!\left(-\frac{(x-\mu)^2}{2\sigma^2}\right)
$$

integrates to one precisely because $I = \sqrt{\pi}$.

| Within | Share of the area |
| :----: | ----------------: |
| $\mu \pm 1\sigma$ | 68.27 % |
| $\mu \pm 2\sigma$ | 95.45 % |
| $\mu \pm 3\sigma$ | 99.73 % |
