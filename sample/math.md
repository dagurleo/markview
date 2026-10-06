# Math

Math is written in TeX between dollar signs, as on GitHub, and drawn natively by SwaTex,
a Swift version of KaTeX.

## Inline

The area of a circle is $A = \pi r^2$, and Euler's identity is $e^{i\pi} + 1 = 0$.
A formula with Markdown characters in it can go between `` $` `` and `` `$ ``:
$`a_1 * b_1 = c_1 * d_1`$. A single dollar is only math when it reads like math, so
this costs $5 and that costs $10, and neither is a formula. Write `\$` for a dollar
sign that would otherwise start one: \$x\$.

Inline math follows the text around it, in **bold text $x^2$**, in a link
[to $\mathbb{R}^n$](#display), as a subscript-heavy $\sum_{i=1}^{n} x_i^2$, and in a
heading:

### The golden ratio $\varphi = \frac{1 + \sqrt{5}}{2}$

## Display

A formula on lines of its own is centred:

$$
\int_{-\infty}^{\infty} e^{-x^2}\,dx = \sqrt{\pi}
$$

$$\frac{d}{dx}\left( \int_{a}^{x} f(t)\,dt \right) = f(x)$$

A `math` code block is the same:

```math
\begin{aligned}
\nabla \cdot \mathbf{E} &= \frac{\rho}{\varepsilon_0} \\
\nabla \cdot \mathbf{B} &= 0 \\
\nabla \times \mathbf{E} &= -\frac{\partial \mathbf{B}}{\partial t} \\
\nabla \times \mathbf{B} &= \mu_0 \mathbf{J} + \mu_0 \varepsilon_0 \frac{\partial \mathbf{E}}{\partial t}
\end{aligned}
```

Numbered equations keep their numbers at the edge. An `align` numbers its rows, counting
on through the document, and `\tag` gives an equation a name of its own:

$$
\begin{align}
(a + b)^2 &= a^2 + 2ab + b^2 \\
(a - b)^2 &= a^2 - 2ab + b^2
\end{align}
$$

$$
E = mc^2 \tag{Einstein}
$$

Matrices and cases:

$$
A = \begin{pmatrix} 1 & 2 & 3 \\ 4 & 5 & 6 \\ 7 & 8 & 9 \end{pmatrix}, \qquad
|x| = \begin{cases} x & x \ge 0 \\ -x & x < 0 \end{cases}
$$

Chemistry, with mhchem's `\ce`:

$$
\ce{2H2 + O2 -> 2H2O}
$$

## In other places

> A quote with math: $\lim_{n \to \infty} \left(1 + \frac{1}{n}\right)^n = e$
>
> $$
> \sum_{n=1}^{\infty} \frac{1}{n^2} = \frac{\pi^2}{6}
> $$

1. A list item with $\sqrt{2} \approx 1.414$.
2. And one with a block:

   $$
   \binom{n}{k} = \frac{n!}{k!\,(n-k)!}
   $$

| Name | Formula |
| --- | --- |
| Pythagoras | $a^2 + b^2 = c^2$ |
| Mass–energy | $E = mc^2$ |
| A pipe inside math | $\lvert x \rvert = |x|$ |

## Mistakes

A formula that cannot be read is shown as written, in grey: $\frac{1}{$, and in code
`$x$` stays code.
