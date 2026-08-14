import CountUp from "./CountUp";

interface Stat {
  valor: number
  sufijo: string
  etiqueta: string
}

interface Props {
  stats: Stat[]
}

export default function StatsCounter({ stats }: Props) {
  return (
    <>
      {stats.map((stat, i) => (
        <div key={i} className="stat__item">

          <div className="stat__numero">
            <CountUp
              from={0}
              to={stat.valor}
              duration={2}
              delay={i * 0.2}
              direction="up"
              separator=","
            />
            <span className="stat__sufijo">{stat.sufijo}</span>
          </div>

          <p className="stat__etiqueta">{stat.etiqueta}</p>

        </div>
      ))}
    </>
  )
}