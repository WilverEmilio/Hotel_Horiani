import React, { useEffect, useState,type ReactNode} from 'react';
import {createPortal} from 'react-dom'
import './detalleHB.css'


interface ModalProps {
    isOpen: boolean
    onClose: () => void
    title: string
    children: ReactNode
}

interface GaleriaProps {
    images: string[]
}
export function GaleriaModal({images}: GaleriaProps){
    const [active, setActive] = useState(0)
    

    return(
        <div className='galeria'>
            <div className='galeria__main'>
                <img src={images[active]} alt={'Foto ${active + 1}'} className='galeria__img' />
                {images.length > 1 &&(
                    <>
                        <button
                        type='button'
                        className='galeria__arrow galeria__arrow--prev'
                        onClick={()=> setActive(i => (i - 1 + images.length)%images.length)}
                        arial-label="Anterior"
                        >
                            ,
                        </button>
                        <button
                        type='button'
                        className='galeria__arrow galeria__arrow--next'
                        onClick={()=> setActive(i => (i + 1)%images.length)}
                        arial-label="Siguiente"
                        >
                            ,
                        </button>
                    </>
                )}
                {images.length>1&&(
                    <span className='galeria__counter'>
                        {active + 1} / {images.length}
                    </span>
                )}
            </div>

            {images.length > 1 && (
                <div className='galeria_thumbs'>
                    {images.map((src,i)=>(
                        <button 
                        key={i}
                        type='button'
                        className={`galeria__thumb${i === active ? " galeria__thumb--active" : ""}`}
                        onClick={()=>setActive(i)}
                        arial-label={`Foto ${i + 1}`}
                        >
                            <img src={src} alt={`Miniatura ${i + 1}`} />
                        </button>
                    ))}
                </div>
            )}
        </div>
    )
}


export const Modal: React.FC<ModalProps> = ({isOpen, onClose, title, children}) => {
    useEffect(()=>{
        const handlekey = (e: KeyboardEvent) => {
            if(e.key == "Escape") onClose()
        }
        if (isOpen) document.addEventListener("keydown", handlekey)
        return() => document.removeEventListener("keydown", handlekey)
    }, [isOpen,onClose])

    useEffect(() =>{
        document.body.style.overflow = isOpen ? "hidden" : ""
        return() => { document.body.style.overflow = ""}
    }, [isOpen])

    if (!isOpen) return null
 
 return createPortal(
    <div className="modal-overlay" onClick={onClose}>
        <div className='modal-container' onClick={(e) => e.stopPropagation()}>
            <div className='modal-header'>
                <h3>{title}</h3>
                <button className='modal-close-btn' onClick={onClose}>&times;</button>
            </div>
            <div className='modal-body'>
                {children}
            </div>
        </div>
    </div>,
    document.body
 )
}
