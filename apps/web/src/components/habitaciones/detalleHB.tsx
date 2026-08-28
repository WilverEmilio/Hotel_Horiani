import React, { useEffect, type ReactNode} from 'react';
import {createPortal} from 'react-dom'
import './detalleHB.css'

interface ModalProps {
    isOpen: boolean
    onClose: () => void
    title: string
    children: ReactNode
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
